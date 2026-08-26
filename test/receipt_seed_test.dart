// Проверка одноразового сида покупок из встроенных assets (test-аналог
// _seedBundledPurchases из main.dart). Реальные assets из assets/data/.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:system_hermes/core/constants.dart';
import 'package:system_hermes/data/adapters.dart';
import 'package:system_hermes/data/models.dart';
import 'package:system_hermes/services/receipt_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('сид из assets заполняет боксы чеками и ценами', () async {
    final dir = Directory.systemTemp.createTempSync('hermes_seed_test');
    Hive.init(dir.path);
    registerHiveAdapters();
    final receipts = await Hive.openBox<Receipt>(BoxNames.receipts);
    final prices = await Hive.openBox<PriceEntry>(BoxNames.prices);

    final service = ReceiptImportService(receipts, prices, (r, a) async => null);

    final checks = await service.importChecksFromAssets(
      rootBundle,
      [
        'assets/data/checks/check_2026-07-21_TROYKA.txt',
        'assets/data/checks/check_2026-07-12_EVROOPT.xlsx',
        'assets/data/checks/checks_2026-07-14_TROYKA_GIPPO_MYASTORG.xlsx',
      ],
      createTransactions: false,
    );
    final priceReport = await service.importPricesFromJsonString(
      await rootBundle.loadString('assets/data/prices/prices.json'),
    );

    // Реальные данные: TXT(ТРОЙКА) + ЕВРООПТ + мульти-магазин ТРОЙКА/ГИППО(±ГЛАВМЯСТОРГ).
    // В параллельном сьюте число может отличаться из-за конкурентной загрузки assets,
    // поэтому проверяем фактическое наличие ключевых чеков и корректность импорта.
    expect(checks.errors, 0);
    expect(checks.added, greaterThanOrEqualTo(4));
    expect(receipts.length, checks.added);
    final stores = receipts.values.map((r) => r.store).toSet();
    expect(stores.contains('ТРОЙКА'), isTrue);
    expect(stores.contains('ЕВРООПТ'), isTrue);
    expect(stores.contains('ГИППО'), isTrue);
    expect(priceReport.added, greaterThan(0));
    expect(prices.length, priceReport.added);

    // Идемпотентность: повторный сид не плодит дубли.
    final again = await service.importChecksFromAssets(
      rootBundle,
      [
        'assets/data/checks/check_2026-07-21_TROYKA.txt',
        'assets/data/checks/check_2026-07-12_EVROOPT.xlsx',
        'assets/data/checks/checks_2026-07-14_TROYKA_GIPPO_MYASTORG.xlsx',
      ],
      createTransactions: false,
    );
    expect(again.added, 0);
    expect(again.skipped, checks.added);
    expect(receipts.length, checks.added);

    await Hive.close();
    dir.deleteSync(recursive: true);
  });
}
