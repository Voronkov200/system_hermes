// Сервис импорта чеков и каталога цен в локальный банк (модуль «Деньги»).
//
// Отвечает за:
//  - обход папки с чеками (TXT / XLSX / JPG-сканы), разбор и сохранение;
//  - создание ОДНОЙ операции `withdrawal` в банке на каждый чек;
//  - импорт JSON-каталога цен с дедупликацией по (shop, name);
//  - идемпотентность: повторный запуск того же файла не плодит дубли и не
//    уменьшает баланс повторно (ключ = sourcePath + store + dateTime + total).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'bank_service.dart';
import 'receipt_parser.dart';

/// Отчёт об импорте: сколько добавлено / пропущено / с ошибками.
class ImportReport {
  final int added;
  final int skipped;
  final int errors;
  final int pendingOcr; // сканы, ожидающие OCR

  const ImportReport({
    this.added = 0,
    this.skipped = 0,
    this.errors = 0,
    this.pendingOcr = 0,
  });

  ImportReport operator +(ImportReport other) => ImportReport(
        added: added + other.added,
        skipped: skipped + other.skipped,
        errors: errors + other.errors,
        pendingOcr: pendingOcr + other.pendingOcr,
      );

  bool get isEmpty =>
      added == 0 && skipped == 0 && errors == 0 && pendingOcr == 0;

  String get summary {
    final parts = <String>[];
    if (added > 0) parts.add('добавлено $added');
    if (skipped > 0) parts.add('пропущено $skipped');
    if (pendingOcr > 0) parts.add('скан OCR $pendingOcr');
    if (errors > 0) parts.add('ошибок $errors');
    return parts.isEmpty
        ? 'ничего не найдено'
        : parts.join(', ');
  }
}

/// Импорт покупок из папки и каталога цен из JSON.
class ReceiptImportService {
  final Box<Receipt> _receipts;
  final Box<PriceEntry> _prices;

  /// Как записать покупку в банк (создать операцию `withdrawal` и вернуть её).
  /// В проде — [BankController.recordPurchase]; в тестах — простая заглушка.
  final Future<Transaction?> Function(Receipt receipt, String accountId)
      _record;

  ReceiptImportService(
    this._receipts,
    this._prices,
    this._record,
  );

  // ------------------------------------------------------------------
  // ЧЕКИ
  // ------------------------------------------------------------------

  /// Обходит папку, парсит поддерживаемые файлы и сохраняет чеки.
  /// [accountId] — счёт/карта, с которого списывается покупка (по умолчанию —
  /// общий BYN-счёт).
  Future<ImportReport> importChecksFromFolder(
    String folderPath, {
    String accountId = Account.generalId,
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      return const ImportReport(errors: 1);
    }
    final keys = _existingReceiptKeys();
    var report = const ImportReport();
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final reportPart = await _importSingleFile(entity, keys, accountId);
      report += reportPart;
    }
    return report;
  }

  /// Импорт конкретных файлов (напр., после выбора через file_picker).
  Future<ImportReport> importChecksFromFiles(
    List<String> paths, {
    String accountId = Account.generalId,
  }) async {
    final keys = _existingReceiptKeys();
    var report = const ImportReport();
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        report = report + const ImportReport(errors: 1);
        continue;
      }
      report = report + await _importSingleFile(file, keys, accountId);
    }
    return report;
  }

  /// Импорт чеков из встроенных assets (для одномоментного сида реальных
  /// данных в приложение без ручного выбора папки). При
  /// [createTransactions] == false чеки сохраняются, но операция `withdrawal`
  /// в банке НЕ создаётся (баланс не меняется).
  Future<ImportReport> importChecksFromAssets(
    AssetBundle bundle,
    List<String> assetPaths, {
    String accountId = Account.generalId,
    bool createTransactions = true,
  }) async {
    final keys = _existingReceiptKeys();
    var report = const ImportReport();
    for (final path in assetPaths) {
      final lower = path.toLowerCase();
      try {
        if (lower.endsWith('.txt')) {
          final rec = parseTxtReceipt(await bundle.loadString(path), path);
          if (rec == null) {
            report = report + const ImportReport(errors: 1);
            continue;
          }
          report = report + await _storeReceipt(rec, keys, accountId,
              createTransaction: createTransactions);
        } else if (lower.endsWith('.xlsx')) {
          final data = await bundle.load(path);
          final bytes =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          final recs = parseXlsxReceipts(bytes, path);
          if (recs.isEmpty) {
            report = report + const ImportReport(errors: 1);
            continue;
          }
          for (final rec in recs) {
            report = report + await _storeReceipt(rec, keys, accountId,
                createTransaction: createTransactions);
          }
        } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
          final rec = _ocrReceiptFromPath(path);
          report = report + await _storeReceipt(rec, keys, accountId,
              createTransaction: createTransactions);
        }
      } catch (_) {
        report = report + const ImportReport(errors: 1);
      }
    }
    return report;
  }

  Future<ImportReport> _importSingleFile(
    File file,
    Set<String> keys,
    String accountId,
  ) async {
    final lower = file.path.toLowerCase();
    final base = file.uri.pathSegments.isEmpty ? '' : file.uri.pathSegments.last;

    try {
      if (lower.endsWith('.txt')) {
        final rec = parseTxtReceipt(await file.readAsString(), file.path);
        if (rec == null) return const ImportReport(errors: 1);
        return await _storeReceipt(rec, keys, accountId);
      }
      if (lower.endsWith('.xlsx')) {
        // Каталог цен (Товары_Магазинов.xlsx) — не чек, пропускаем.
        if (base.toLowerCase().contains('товары')) {
          return const ImportReport();
        }
        final recs = parseXlsxReceipts(await file.readAsBytes(), file.path);
        if (recs.isEmpty) return const ImportReport(errors: 1);
        var report = const ImportReport();
        for (final rec in recs) {
          report = report + await _storeReceipt(rec, keys, accountId);
        }
        return report;
      }
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        // Скан: не выдумываем товары без распознавания, помечаем под OCR.
        return await _storeReceipt(_ocrReceiptFromPath(file.path), keys, accountId);
      }
      return const ImportReport();
    } catch (_) {
      return const ImportReport(errors: 1);
    }
  }

  /// Сохраняет чек идемпотентно. При успехе создаёт одну операцию `withdrawal`
  /// (для сканов и чеков без суммы — только помечает, операцию не создаёт).
  /// Если [createTransaction] == false, операция не создаётся вовсе (сид
  /// исторических данных без изменения баланса).
  Future<ImportReport> _storeReceipt(
    Receipt rec,
    Set<String> keys,
    String accountId, {
    bool createTransaction = true,
  }) async {
    if (keys.contains(rec.dedupKey)) return const ImportReport(skipped: 1);
    keys.add(rec.dedupKey);

    // Сначала — чек, при успехе — операция.
    await _receipts.put(rec.id, rec);

    if (rec.needsOcr || rec.total <= 0) {
      return ImportReport(added: 1, pendingOcr: rec.needsOcr ? 1 : 0);
    }
    if (!createTransaction) {
      return const ImportReport(added: 1);
    }

    final txn = await _record(rec, accountId);
    if (txn == null) return const ImportReport(added: 1, errors: 1);

    await _receipts.put(rec.id, rec.copyWith(transactionId: txn.id));
    return const ImportReport(added: 1);
  }

  Set<String> _existingReceiptKeys() =>
      _receipts.values.map((r) => r.dedupKey).toSet();

  /// Скан-фактура: магазин и дату пытаемся вытащить из имени файла
  /// (Чек_2026-07-16_ФиксПрайс.jpg → «ФиксПрайс», 16.07.2026).
  Receipt _ocrReceiptFromPath(String path) {
    final base = path.split(RegExp(r'[/\\]')).last;
    final now = DateTime.now();
    String store = 'Скан чека';
    DateTime? date;
    final m = RegExp(
        r'^Чек[аи-]*[_\s]*(\d{4}-\d{2}-\d{2})?[_\s]*(.+?)(?:_\d{2,})?\.[a-z0-9]+$',
        caseSensitive: false).firstMatch(base);
    if (m != null) {
      if (m.group(1) != null) date = parseDate(m.group(1)!);
      final s = m.group(2)?.trim() ?? '';
      if (s.isNotEmpty && !s.contains('.')) store = s;
    }
    return markOcrReceipt(store: store, date: date, sourcePath: path, now: now);
  }

  // ------------------------------------------------------------------
  // СИНК (GitHub-мост): канонический JSON от агента
  // ------------------------------------------------------------------

  /// Импорт каталога чеков из канонического JSON (data/receipts.json),
  /// который агент (PCLite) публикует в GitHub, а приложение подтягивает.
  ///
  /// Формат записи (обязательно для издателя):
  /// {"store":"ТРОЙКА","address":"ул. Крупской, 119","dateTime":"21.07.2026 12:52",
  ///  "total":11.58,"discount":0,"paymentMethod":"карта","sourceType":"ocr",
  ///  "confidence":0.93,
  ///  "items":[{"name":"Пакет майка","qty":1,"unitPrice":0.29,"amount":0.29}]}
  ///
  /// Честность OCR: если [confidence] отсутствует или < 0.8 — чек помечается
  /// [Receipt.needsOcr] = true, и в приложении показывается «требует проверки»,
  /// а не выдумываются данные при низкой уверенности распознавания.
  ///
  /// Дедупликация — по (store, dateTime, total): не плодит дубли при повторном
  /// пулле и не конфликтует с чеками, добавленными из assets (другой sourcePath).
  /// Операции в банке НЕ создаются (синк только наполняет «Покупки»,
  /// баланс не меняется).
  Future<ImportReport> importReceiptsFromJsonString(String content) async {
    final decoded = jsonDecode(content);
    if (decoded is! List) return const ImportReport(errors: 1);

    // Существующие отпечатки (store|isoDate|total) из бокса — чтобы не
    // дублировать чеки, уже добавленные сидом из assets (у них другой sourcePath).
    final seen = <String, Receipt>{
      for (final r in _receipts.values)
        '${r.store}||${r.dateTime.toIso8601String()}||${r.total}': r,
    };

    final nowActual = DateTime.now();
    var report = const ImportReport();

    for (final raw in decoded) {
      if (raw is! Map) continue;
      try {
        final store = (raw['store'] as String?)?.trim() ?? 'Скан чека';
        final dateTime = parseDate(raw['dateTime'] ?? raw['date']) ?? nowActual;
        final total = num.tryParse('${raw['total']}')?.toDouble() ?? 0;
        final discount =
            num.tryParse('${raw['discount'] ?? 0}')?.toDouble() ?? 0;
        final payment = (raw['paymentMethod'] as String?)?.trim();
        final confidence = num.tryParse('${raw['confidence']}')?.toDouble();
        // Низкая уверенность / нет данных → «требует проверки».
        final needsOcr = confidence == null || confidence < 0.8;

        final fingerprint = '$store||${dateTime.toIso8601String()}||$total';
        if (seen.containsKey(fingerprint)) {
          report = report + const ImportReport(skipped: 1);
          continue;
        }

        final items = <ReceiptItem>[];
        final rawItems = raw['items'];
        if (rawItems is List) {
          var order = 0;
          for (final it in rawItems) {
            if (it is! Map) continue;
            final name = (it['name'] as String?)?.trim() ?? '';
            if (name.isEmpty) continue;
            order++;
            final qty = num.tryParse('${it['qty'] ?? it['quantity'] ?? 1}')
                    ?.toDouble() ??
                1;
            final unitPrice =
                num.tryParse('${it['unitPrice'] ?? 0}')?.toDouble() ?? 0;
            final amount = num.tryParse('${it['amount'] ?? qty * unitPrice}')
                    ?.toDouble() ??
                0;
            items.add(ReceiptItem(
              order: order,
              name: name,
              quantity: qty,
              unitPrice: unitPrice,
              amount: amount,
            ));
          }
        }

        final receipt = Receipt(
          id: 'sync-receipt::$fingerprint',
          store: store,
          address: (raw['address'] as String?)?.trim(),
          dateTime: dateTime,
          total: total,
          discount: discount,
          paymentMethod: payment,
          items: items,
          sourcePath: 'github-receipts',
          sourceType: (raw['sourceType'] as String?) ?? 'ocr',
          needsOcr: needsOcr,
          importedAt: nowActual,
        );

        await _receipts.put(receipt.id, receipt);
        seen[fingerprint] = receipt;
        if (receipt.needsOcr || receipt.total <= 0) {
          report = report +
              ImportReport(added: 1, pendingOcr: receipt.needsOcr ? 1 : 0);
        } else {
          report = report + const ImportReport(added: 1);
        }
      } catch (_) {
        report = report + const ImportReport(errors: 1);
      }
    }
    await _receipts.flush();
    return report;
  }

  // ------------------------------------------------------------------
  // ЦЕНЫ
  // ------------------------------------------------------------------

  /// Импорт каталога цен из JSON-файла (дедупликация по shop+name).
  Future<ImportReport> importPricesFromJson(String jsonPath) async {
    final file = File(jsonPath);
    if (!await file.exists()) return const ImportReport(errors: 1);
    return _importPrices(await file.readAsString());
  }

  /// Импорт каталога цен из строки JSON (полезно для тестов и bytes из picker).
  Future<ImportReport> importPricesFromJsonString(String content) =>
      _importPrices(content);

  Future<ImportReport> _importPrices(String content) async {
    final entries = parsePricesJson(content);
    if (entries.isEmpty) return const ImportReport(errors: 1);

    // Дедуп по (shop, name) через карту: словарь строится один раз и сразу
    // пополняется, поэтому повторный импорт того же файла не плодит дубли.
    final prices =
        <String, PriceEntry>{for (final p in _prices.values) '${p.shop}||${p.name}': p};

    var report = const ImportReport();
    for (final e in entries) {
      final key = '${e.shop}||${e.name}';
      final existing = prices[key];
      if (existing == null) {
        // Стабильный id по ключу (shop+name): гарантирует уникальность при
        // массовой вставке (genId() даёт коллизии в одном микросекундном тике)
        // и не плодит дубли при повторном импорте.
        final id = 'price::${e.shop}::${e.name}';
        final fresh = PriceEntry(
          id: id,
          shop: e.shop,
          name: e.name,
          price: e.price,
          oldPrice: e.oldPrice,
          discount: e.discount,
          date: e.date,
          updatedAt: e.updatedAt,
        );
        await _prices.put(id, fresh);
        prices[key] = fresh;
        report = report + const ImportReport(added: 1);
      } else {
        // Обновляем существующую запись (не создаём дубль), сохраняя её id.
        await _prices.put(
          existing.id,
          PriceEntry(
            id: existing.id,
            shop: e.shop,
            name: e.name,
            price: e.price,
            oldPrice: e.oldPrice,
            discount: e.discount,
            date: e.date,
            updatedAt: e.updatedAt,
          ),
        );
        report = report + const ImportReport(skipped: 1);
      }
    }
    await _prices.flush();
    return report;
  }
}

// ---------------------------------------------------------------------
// Riverpod-провайдеры (реактивные списки чеков и цен)
// ---------------------------------------------------------------------

/// Сервис импорта, завязанный на открытые боксы и текущий банк.
final receiptImportServiceProvider = Provider<ReceiptImportService>((ref) {
  return ReceiptImportService(
    Hive.box<Receipt>(BoxNames.receipts),
    Hive.box<PriceEntry>(BoxNames.prices),
    (receipt, accountId) => ref
        .read(bankProvider.notifier)
        .recordPurchase(receipt: receipt, accountId: accountId),
  );
});

List<Receipt> _sortReceipts(Box<Receipt> box) {
  final list = box.values.toList()
    ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  return list;
}

/// Последние чеки (сортировка по дате), обновляется при изменении бокса.
final receiptsProvider = StreamProvider<List<Receipt>>((ref) {
  final box = Hive.box<Receipt>(BoxNames.receipts);
  return Stream<List<Receipt>>.multi((controller) {
    controller.add(_sortReceipts(box));
    final sub = box.watch().listen((_) => controller.add(_sortReceipts(box)));
    controller.onCancel = sub.cancel;
  });
});
