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
      Account.generalId,
      Account(
        id: Account.generalId,
        name: 'Общий счёт',
        currency: 'BYN',
        balance: 100,
      ),
    );
    await accounts.put(
      'fuel',
      Account(
        id: 'fuel',
        name: 'Старый рублёвый счёт',
        currency: 'BYN',
        balance: 450,
      ),
    );
    await accounts.put(
      Account.cardId('USD'),
      Account(
        id: Account.cardId('USD'),
        name: 'Виртуальная карта USD',
        currency: 'USD',
        type: 'card',
        balance: 5,
      ),
    );
    await accounts.put(
      'assets',
      Account(
        id: 'assets',
        name: 'Старая валютная карта',
        currency: 'USD',
        balance: 21,
      ),
    );
    await transactions.add(
      Transaction(
        id: 'legacy-operation',
        type: 'deposit',
        amount: 450,
        currency: 'BYN',
        date: DateTime(2026, 8, 1),
        description: 'Пенсия → Топливо для разработки',
      ),
    );

    final scope = await makeContainer();
    final state = scope.read(bankProvider);

    expect(state.generalAccount?.balance, 550);
    expect(state.cardFor('USD')?.balance, 26);
    expect(state.byId('fuel'), isNull);
    expect(state.byId('assets'), isNull);
    expect(
      state.transactions.single.description,
      'Пенсия → Общий счёт',
    );
  });

  test('ручное пополнение меняет выбранный баланс и пишет операцию', () async {
    final scope = await makeContainer();
    final controller = scope.read(bankProvider.notifier);

    final error = await controller.deposit(
      accountId: Account.generalId,
      amount: 125.50,
      note: 'Фриланс-заказ',
    );

    final state = scope.read(bankProvider);
    expect(error, isNull);
    expect(state.generalAccount?.balance, 125.50);
    final deposit =
        state.transactions.firstWhere((entry) => entry.type == 'deposit');
    expect(deposit.amount, 125.50);
    expect(deposit.description, 'Фриланс-заказ → Общий счёт');
  });

  test('ручное пополнение отклоняет нулевую и отрицательную сумму', () async {
    final scope = await makeContainer();
    final controller = scope.read(bankProvider.notifier);

    expect(
      await controller.deposit(accountId: Account.generalId, amount: 0),
      isNotNull,
    );
    expect(
      await controller.deposit(accountId: Account.generalId, amount: -10),
      isNotNull,
    );
    expect(scope.read(bankProvider).generalAccount?.balance, 0);
  });
}
