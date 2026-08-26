// Тесты импорта чеков и каталога цен.
//
// Используются ТОЛЬКО реальные данные из файлов-примеров (test/fixtures/),
// скопированных из F:\Чеки и F:\Цены. Никаких выдуманных чисел.
//
// Проверяем:
//  - парсер TXT (одно-магазинный чек ТРОЙКА);
//  - парсер XLSX одно-магазинный (ЕВРООПТ);
//  - парсер XLSX мульти-магазинный (ТРОЙКА_ГИППО_МЯСТОРГ) + лист «Сводка» не
//    задваивает позиции;
//  - парсер JSON-каталога цен;
//  - идемпотентность повторного импорта (двойной импорт → 1 операция).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:system_hermes/core/constants.dart';
import 'package:system_hermes/data/adapters.dart';
import 'package:system_hermes/data/models.dart';
import 'package:system_hermes/services/receipt_import_service.dart';
import 'package:system_hermes/services/receipt_parser.dart';

/// Путь к фикстурам относительно корня проекта (flutter test запускается из него).
String fixture(String name) => 'test/fixtures/$name';

void main() {
  group('Парсеры', () {
    test('TXT: чек ТРОЙКА 21.07.2026', () {
      final rec = parseTxtReceipt(
        File(fixture('Чек_2026-07-21_ТРОЙКА.txt')).readAsStringSync(),
        'Чек_2026-07-21_ТРОЙКА.txt',
        now: DateTime(2026, 8, 26),
      );
      expect(rec, isNotNull);
      expect(rec!.store, 'ТРОЙКА');
      expect(rec.address, 'г. Могилёв, ул. Крупской, 119');
      expect(rec.dateTime, DateTime(2026, 7, 21, 12, 52));
      expect(rec.total, 11.58);
      expect(rec.paymentMethod, 'карта');
      expect(rec.sourceType, 'txt');
      expect(rec.needsOcr, isFalse);
      expect(rec.items.length, 9);

      // Реальные позиции из файла.
      final ogurec = rec.items.firstWhere((i) => i.order == 2);
      expect(ogurec.name, 'Огурец свежий колючий, РБ (0.506 кг × 1.99)');
      expect(ogurec.quantity, 0.506);
      expect(ogurec.unitPrice, 1.99);
      expect(ogurec.amount, 1.01);

      // Ключ идемпотентности включает sourcePath + store + dateTime + total.
      expect(
        rec.dedupKey,
        'Чек_2026-07-21_ТРОЙКА.txt\u241FТРОЙКА\u241F'
        '2026-07-21T12:52:00.000\u241F11.58',
      );
    });

    test('XLSX одно-магазинный: чек ЕВРООПТ 12.07.2026', () {
      final recs = parseXlsxReceipts(
        File(fixture('Чек_2026-07-12_ЕВРООПТ.xlsx')).readAsBytesSync(),
        'Чек_2026-07-12_ЕВРООПТ.xlsx',
        now: DateTime(2026, 8, 26),
      );
      expect(recs.length, 1);
      final rec = recs.single;
      expect(rec.store, 'ЕВРООПТ');
      expect(rec.dateTime, DateTime(2026, 7, 12, 15, 55));
      expect(rec.total, 38.35);
      expect(rec.items.length, 9);

      final kvass = rec.items.firstWhere((i) => i.order == 1);
      expect(kvass.name, 'Квас «Дарид» тёмный');
      expect(kvass.quantity, 1);
      expect(kvass.unitPrice, 1.93);
      expect(kvass.amount, 1.93);
    });

    test('XLSX мульти-магазинный: ТРОЙКА + ГИППО (Сводка не дублирует)', () {
      final recs = parseXlsxReceipts(
        File(fixture('Чеки_2026-07-14_ТРОЙКА_ГИППО_МЯСТОРГ.xlsx'))
            .readAsBytesSync(),
        'Чеки_2026-07-14_ТРОЙКА_ГИППО_МЯСТОРГ.xlsx',
        now: DateTime(2026, 8, 26),
      );
      // Один чек на магазин; лист «Сводка» пропускается — дублей нет.
      expect(recs.length, 3);

      final troika = recs.firstWhere((r) => r.store == 'ТРОЙКА');
      expect(troika.total, 53.54);
      expect(troika.items.length, 22);
      // Позиция со скидкой сохраняет и цену за единицу, и сумму, и скидку.
      final corn = troika.items.firstWhere((i) => i.order == 3);
      expect(corn.name, 'Кукуруза сладкая Botanica 425мл');
      expect(corn.unitPrice, 3.49);
      expect(corn.amount, 3.19);
      expect(corn.discount, 0.30);

      final hippo = recs.firstWhere((r) => r.store == 'ГИППО');
      expect(hippo.total, 6.36);
      expect(hippo.items.length, 3);

      // Суммарная сумма по магазинам не должна появляться отдельным чеком.
      final stores = recs.map((r) => r.store).toSet();
      expect(stores.contains('ВСЕГО'), isFalse);
      expect(stores.contains('Сводка'), isFalse);
    });

    test('JSON: каталог цен all_products_clean', () {
      final prices = parsePricesJson(
        File(fixture('all_products_clean.json')).readAsStringSync(),
        now: DateTime(2026, 8, 26),
      );
      expect(prices, isNotEmpty);
      final first = prices.first;
      expect(first.shop, 'Белторг');
      expect(first.name, 'Итальянские травы Аквилео 8 г');
      expect(first.price, 1.45);
      expect(first.date, DateTime(2026, 7, 15));
    });
  });

  group('Сервис импорта (идемпотентность)', () {
    late Directory tempDir;
    late Directory receiptsDir;
    late Box<Receipt> receipts;
    late Box<PriceEntry> prices;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('hermes_receipt_test');
      Hive.init(tempDir.path);
      registerHiveAdapters();
      receiptsDir = Directory('${tempDir.path}/checks');
      receiptsDir.createSync(recursive: true);
      // Кладём реальный TXT-чек в тестовую папку.
      File(fixture('Чек_2026-07-21_ТРОЙКА.txt'))
          .copySync('${receiptsDir.path}/Чек_2026-07-21_ТРОЙКА.txt');
      receipts = await Hive.openBox<Receipt>(BoxNames.receipts);
      prices = await Hive.openBox<PriceEntry>(BoxNames.prices);
    });

    setUp(() async {
      await receipts.clear();
      await prices.clear();
    });

    tearDownAll(() async {
      await Hive.close();
      tempDir.deleteSync(recursive: true);
    });

    test('двойной импорт того же чека → 1 операция и 1 чек', () async {
      var recordCalls = 0;
      final service = ReceiptImportService(
        receipts,
        prices,
        (receipt, accountId) async {
          recordCalls++;
          return Transaction(
            id: 'txn-$recordCalls',
            type: 'withdrawal',
            amount: receipt.total,
            currency: 'BYN',
            date: receipt.dateTime,
            description: '${receipt.store}, 21.07.2026 12:52',
          );
        },
      );

      final first = await service.importChecksFromFolder(receiptsDir.path);
      expect(first.added, 1);
      expect(first.skipped, 0);
      expect(recordCalls, 1);
      expect(receipts.length, 1);
      // На чеке стоит обратная ссылка на операцию.
      expect(receipts.values.single.transactionId, 'txn-1');

      // Повторный импорт того же файла — дублей не создаёт, баланс не меняется.
      final second = await service.importChecksFromFolder(receiptsDir.path);
      expect(second.added, 0);
      expect(second.skipped, 1);
      expect(recordCalls, 1); // операция НЕ создаётся повторно
      expect(receipts.length, 1);
    });

    test('импорт JSON-цен: дедупликация по (shop, name)', () async {
      final service = ReceiptImportService(
        receipts,
        prices,
        (r, a) async => null,
      );

      final jsonPath = fixture('all_products_clean.json');
      final first = await service.importPricesFromJson(jsonPath);
      expect(first.added, greaterThan(0));
      expect(first.skipped, 0);
      final countAfterFirst = prices.length;

      // Повторный импорт того же файла: новые не создаются, существующие
      // обновляются (в отчёте помечаются как пропущенные).
      final second = await service.importPricesFromJson(jsonPath);
      expect(second.added, 0);
      expect(second.skipped, countAfterFirst);
      expect(prices.length, countAfterFirst);
    });
  });
}
