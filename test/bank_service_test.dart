import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_hermes/core/constants.dart';
import 'package:system_hermes/data/adapters.dart';
import 'package:system_hermes/data/models.dart';
import 'package:system_hermes/services/bank_service.dart';
import 'package:system_hermes/services/settings_service.dart';

void main() {
  late Directory directory;
  late Box<Account> accounts;
  late Box<Transaction> transactions;
  ProviderContainer? container;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('hermes_bank_test');
    Hive.init(directory.path);
    Hive.registerAdapter(AccountAdapter());
    Hive.registerAdapter(TransactionAdapter());
    accounts = await Hive.openBox<Account>(BoxNames.accounts);
    transactions =
        await Hive.openBox<Transaction>(BoxNames.transactions);
  });

  setUp(() async {
    await accounts.clear();
    await transactions.clear();
    SharedPreferences.setMockInitialValues({
      PrefKeys.pensionDay: 28,
    });
  });

  tearDown(() {
    container?.dispose();
    container = null;
  });

  tearDownAll(() async {
    await Hive.close();
    directory.deleteSync(recursive: true);
  });

  Future<ProviderContainer> makeContainer() async {
    final preferences = await SharedPreferences.getInstance();
    final result = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    result.read(bankProvider);
    await Future<void>.delayed(Duration.zero);
    container = result;
    return result;
  }

  test('пенсия 390 BYN начисляется на общий счёт один раз в месяц',
      () async {
    final scope = await makeContainer();
    final controller = scope.read(bankProvider.notifier);

    await controller.checkPension(at: DateTime(2026, 8, 28));
    await controller.checkPension(at: DateTime(2026, 8, 30));

    final state = scope.read(bankProvider);
    expect(state.generalAccount?.balance, 390);
    expect(
      state.transactions.where((entry) => entry.type == 'pension').length,
      1,
    );
  });

  test('старые балансы переносятся в общий счёт и валютную карту', () async {
    await accounts.put(
      Account.fuelId,
      Account(
        id: Account.fuelId,
        name: 'Топливо разработки',
        currency: 'BYN',
        balance: 450,
      ),
    );
    await accounts.put(
      Account.assetsId,
      Account(
        id: Account.assetsId,
        name: 'Твердые активы',
        currency: 'USD',
        balance: 21,
      ),
    );

    final scope = await makeContainer();
    final state = scope.read(bankProvider);

    expect(state.generalAccount?.balance, 450);
    expect(state.cardFor('USD')?.balance, 21);
    expect(state.byId(Account.fuelId), isNull);
    expect(state.byId(Account.assetsId), isNull);
  });
}
