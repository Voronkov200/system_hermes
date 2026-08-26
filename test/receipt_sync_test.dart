// Тесты приёмника синхронизации чеков из GitHub-каталога (data/receipts.json).
//
// Проверяем:
//  - разбор канонической записи (магазин, адрес, дата-время «21.07.2026 12:52»,
//    сумма, способ оплаты, позиции с qty/unitPrice/amount);
//  - честность OCR: низкая уверенность → needsOcr (в UI «требует проверки»);
//  - идемпотентность повторного пулла (один и тот же чек не дублируется);
//  - кросс-источник: чек, добавленный сидом из assets с другим sourcePath и
//    теми же store+dateTime+total, не дублируется синком.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:system_hermes/core/constants.dart';
import 'package:system_hermes/data/adapters.dart';
import 'package:system_hermes/data/models.dart';
import 'package:system_hermes/services/receipt_import_service.dart';

const _jsonHighConf = '''
[
  {"store":"ТРОЙКА","address":"ул. Крупской, 119","dateTime":"21.07.2026 12:52",
   "total":11.58,"discount":0,"paymentMethod":"карта","sourceType":"ocr",
   "confidence":0.93,
   "items":[{"name":"Пакет майка","qty":1,"unitPrice":0.29,"amount":0.29}]}
]
''';

const _jsonLowConf = '''
[
  {"store":"СОСЕДИ","dateTime":"21.07.2026 12:52","total":11.58,
   "sourceType":"ocr","confidence":0.45,
   "items":[{"name":"Хлеб","qty":1,"unitPrice":2.10,"amount":2.10}]}
]
''';

void main() {
  group('Синк-импорт чеков из канонического JSON', () {
    late Directory tempDir;
    late Box<Receipt> receipts;
    late Box<PriceEntry> prices;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('hermes_sync_test');
      Hive.init(tempDir.path);
      registerHiveAdapters();
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

    ReceiptImportService service() => ReceiptImportService(
          receipts,
          prices,
          (r, a) async => null, // синк не создаёт операций в банке
        );

    test('разбор канонической записи (высокая уверенность)', () async {
      final report = await service().importReceiptsFromJsonString(_jsonHighConf);
      expect(report.added, 1);
      expect(report.skipped, 0);
      expect(report.pendingOcr, 0);

      final rec = receipts.values.single;
      expect(rec.store, 'ТРОЙКА');
      expect(rec.address, 'ул. Крупской, 119');
      expect(rec.dateTime, DateTime(2026, 7, 21, 12, 52));
      expect(rec.total, 11.58);
      expect(rec.discount, 0);
      expect(rec.paymentMethod, 'карта');
      expect(rec.sourceType, 'ocr');
      expect(rec.sourcePath, 'github-receipts');
      expect(rec.needsOcr, isFalse);
      expect(rec.items.length, 1);

      final item = rec.items.single;
      expect(item.order, 1);
      expect(item.name, 'Пакет майка');
      expect(item.quantity, 1);
      expect(item.unitPrice, 0.29);
      expect(item.amount, 0.29);

      // Синк не создаёт операцию в банке.
      expect(rec.transactionId, isNull);
    });

    test('низкая уверенность → needsOcr («требует проверки») и pendingOcr', () async {
      final report = await service().importReceiptsFromJsonString(_jsonLowConf);
      expect(report.added, 1);
      expect(report.pendingOcr, 1);

      final rec = receipts.values.single;
      expect(rec.needsOcr, isTrue);
      expect(rec.items.length, 1);
    });

    test('импорт без confidence → needsOcr (не выдумываем при отсутствии данных)', () async {
      const jsonNoConf = '''
[
  {"store":"МАГАЗИН","dateTime":"21.07.2026 12:52","total":5.00,
   "sourceType":"ocr","items":[{"name":"Вода","qty":1,"unitPrice":1.00,"amount":1.00}]}
]
''';
      final report = await service().importReceiptsFromJsonString(jsonNoConf);
      expect(report.pendingOcr, 1);
      expect(receipts.values.single.needsOcr, isTrue);
    });

    test('повторный пулл того же JSON идемпотентен (нет дублей)', () async {
      final s = service();
      final first = await s.importReceiptsFromJsonString(_jsonHighConf);
      expect(first.added, 1);
      expect(receipts.length, 1);

      final second = await s.importReceiptsFromJsonString(_jsonHighConf);
      expect(second.added, 0);
      expect(second.skipped, 1);
      expect(receipts.length, 1); // не задвоился
    });

    test('кросс-источник: сид из assets с теми же store+дата+сумма не дублируется', () async {
      // Сид кладёт чек с реальным sourcePath (assets), синк — с 'github-receipts'.
      final assetLike = Receipt(
        id: 'seed-1',
        store: 'ТРОЙКА',
        address: 'г. Могилёв, ул. Крупской, 119',
        dateTime: DateTime(2026, 7, 21, 12, 52),
        total: 11.58,
        paymentMethod: 'карта',
        items: [
          ReceiptItem(order: 1, name: 'Пакет майка', quantity: 1, unitPrice: 0.29, amount: 0.29),
        ],
        sourcePath: 'assets/data/checks/check.txt',
        sourceType: 'txt',
        importedAt: DateTime(2026, 8, 26),
      );
      await receipts.put(assetLike.id, assetLike);
      expect(receipts.length, 1);

      // Синк того же чека (другой sourcePath) не должен создать дубль.
      final report = await service().importReceiptsFromJsonString(_jsonHighConf);
      expect(report.added, 0);
      expect(report.skipped, 1);
      expect(receipts.length, 1);
    });

    test('некорректный ввод → errors, без падения', () async {
      final report = await service().importReceiptsFromJsonString('{ "not": "array" }');
      expect(report.errors, 1);
      expect(receipts.length, 0);
    });
  });
}
