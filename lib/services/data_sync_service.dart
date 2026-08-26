// Сервис синхронизации данных («Деньги» → «Покупки»/«Цены») из GitHub-моста.
//
// Канальный план: агент (PCLite) публикует распознанные чеки и каталог цен в
// data/receipts.json и data/prices.json своего GitHub-репозитория, а
// приложение по триггерам (запуск / pull-to-refresh / таймер 24ч / вручную)
// тянет их и делает upsert в локальные Hive-боксы. Источник и издатель — агент;
// транспорт — GitHub raw; читатель — приложение (pull). Это единственное
// надёжное пересечение между Telegram-ботом (приём фото) и приложением.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'receipt_import_service.dart';
import 'settings_service.dart';

/// Итог синхронизации: сколько чеков/цен добавлено, были ли ошибки сети.
class SyncResult {
  final bool ok;
  final String? error;
  final ImportReport receipts;
  final ImportReport prices;

  const SyncResult({
    this.ok = true,
    this.error,
    this.receipts = const ImportReport(),
    this.prices = const ImportReport(),
  });

  String get summary {
    if (!ok && error != null) return 'ошибка: $error';
    return 'чек: ${receipts.summary}; цены: ${prices.summary}';
  }
}

/// Подтягивает data/receipts.json и data/prices.json и делает upsert.
class DataSyncService {
  final http.Client _client;
  final ReceiptImportService _importer;

  DataSyncService(this._client, this._importer);

  /// Синхронизация под текущие настройки: уважает выключатель и вычисляет базу.
  Future<SyncResult> syncFromSettings(SettingsState settings) async {
    if (!settings.syncEnabled) {
      return const SyncResult(ok: true, error: 'Синк выключен');
    }
    return sync(baseUrl: settings.syncDataBaseUrl);
  }

  /// Тянет оба каталога данных из [baseUrl] (base `.../data/`).
  Future<SyncResult> sync({required String baseUrl}) async {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    var receipts = const ImportReport();
    var prices = const ImportReport();
    String? error;
    var ok = true;

    try {
      final body = await _fetch('${base}receipts.json');
      if (body == null) {
        if (ok) error = 'receipts.json: HTTP ошибка';
        ok = false;
      } else {
        receipts = await _importer.importReceiptsFromJsonString(body);
      }
    } catch (e) {
      if (ok) error = 'receipts.json: $e';
      ok = false;
    }

    try {
      final body = await _fetch('${base}prices.json');
      if (body == null) {
        if (ok) error = 'prices.json: HTTP ошибка';
        ok = false;
      } else {
        prices = await _importer.importPricesFromJsonString(body);
      }
    } catch (e) {
      if (ok) error = 'prices.json: $e';
      ok = false;
    }

    return SyncResult(ok: ok, error: error, receipts: receipts, prices: prices);
  }

  Future<String?> _fetch(String url) async {
    final resp = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) return resp.body;
    return null;
  }
}

/// Реактивный доступ к синку для экрана и автозапуска.
final dataSyncServiceProvider = Provider<DataSyncService>((ref) {
  return DataSyncService(
    http.Client(),
    ref.watch(receiptImportServiceProvider),
  );
});
