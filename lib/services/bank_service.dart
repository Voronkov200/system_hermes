// Модуль "Центральный Банк Тима": счета, транзакции, пенсия, конвертация.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'nbrb_api.dart';
import 'settings_service.dart';

/// Состояние банка.
class BankState {
  final List<Account> accounts;
  final List<Transaction> transactions;

  /// Момент последнего поступления средств (для анимации "Сейфа").
  final DateTime? depositFlash;

  /// Описание последнего события (например, штраф или пенсия).
  final String? lastEvent;

  const BankState({
    required this.accounts,
    required this.transactions,
    this.depositFlash,
    this.lastEvent,
  });

  Account? byId(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  double totalByn({List<CurrencyRate>? rates, String assetsCurrency = 'USD'}) {
    double total = 0;
    for (final a in accounts) {
      if (a.currency == 'BYN') {
        total += a.balance;
      } else {
        final rate = NbrbApi.rateOf(rates, a.currency);
        if (rate != null) total += a.balance * rate;
      }
    }
    return total;
  }
}

/// Контроллер банка: логика счетов, пенсии, штрафов и бонусов.
class BankController extends Notifier<BankState> {
  late final Box<Account> _accounts;
  late final Box<Transaction> _transactions;

  @override
  BankState build() {
    _accounts = Hive.box<Account>(BoxNames.accounts);
    _transactions = Hive.box<Transaction>(BoxNames.transactions);
    _ensureDefaults();
    // Проверка пенсии при старте/открытии экрана.
    Future.microtask(checkPension);
    return _readState();
  }

  // ---------------------------------------------------------------- чтение

  BankState _readState() => BankState(
        accounts: List.of(_accounts.values),
        transactions: _transactions.values.toList()
          ..sort((a, b) => b.date.compareTo(a.date)),
      );

  // ------------------------------------------------------------- дефолты

  void _ensureDefaults() {
    if (_accounts.isNotEmpty) return;
    final s = ref.read(settingsProvider);
    final fuel = Account(
      id: Account.fuelId,
      name: 'Топливо разработки',
      currency: 'BYN',
      balance: 0,
    );
    final assets = Account(
      id: Account.assetsId,
      name: 'Твердые активы',
      currency: s.assetsCurrency,
      balance: 0,
    );
    _accounts.put(fuel.id, fuel);
    _accounts.put(assets.id, assets);
    _logTransaction('deposit', 0, 'BYN', 'Открытие счетов Банка');
  }

  void _logTransaction(String type, double amount, String currency,
      String? description,
      {double? rate}) {
    _transactions.add(Transaction(
      id: genId(),
      type: type,
      amount: amount,
      currency: currency,
      date: DateTime.now(),
      description: description,
      rate: rate,
    ));
  }

  // ---------------------------------------------------------------- пенсия

  /// Ежемесячное начисление 450 BYN с автораспределением:
  /// 50 BYN -> "Топливо разработки", остальное -> "Твердые активы" (USD/EUR).
  Future<void> checkPension() async {
    final s = ref.read(settingsProvider);
    final now = DateTime.now();
    final month = '${now.year}-${now.month}';
    if (s.lastPensionMonth == month) return;
    if (now.day < s.pensionDay) return;

    final fuelShare = s.fuelShare;
    final toAssets = s.pensionAmount - fuelShare;
    final rates = await ref.read(nbrbApiProvider).fetchRates().catchError((_) => <CurrencyRate>[]);

    final fuel = _accounts.get(Account.fuelId);
    if (fuel == null) return;
    fuel.balance += fuelShare;
    _accounts.put(fuel.id, fuel);
    _logTransaction('deposit', fuelShare, 'BYN',
        'Пенсия: часть на Топливо разработки');

    final assets = _accounts.get(Account.assetsId);
    if (assets != null) {
      final rate = NbrbApi.rateOf(rates, assets.currency);
      if (rate != null && toAssets > 0) {
        final converted = toAssets / rate;
        assets.balance += converted;
        _accounts.put(assets.id, assets);
        _logTransaction('conversion', toAssets, 'BYN',
            'Пенсия: конвертация в ${assets.currency}',
            rate: rate);
        _logTransaction('deposit', converted, assets.currency,
            'Пенсия: зачислено в Твердые активы');
      } else if (toAssets > 0) {
        fuel.balance += toAssets;
        _accounts.put(fuel.id, fuel);
        _logTransaction('deposit', toAssets, 'BYN',
            'Пенсия: курс недоступен, остаток на Топливе');
      }
    }

    await ref.read(settingsProvider.notifier).setLastPensionMonth(month);
    final next = _readState();
    state = BankState(
      accounts: next.accounts,
      transactions: next.transactions,
      depositFlash: DateTime.now(),
      lastEvent: 'Поступление пенсии: ${fmtAmount(s.pensionAmount)} BYN',
    );
  }

  // ----------------------------------------------------------- конвертация

  /// Перевод между счетами с конвертацией по актуальному курсу.
  Future<String?> convert(
      String fromId, String toId, double amount, List<CurrencyRate>? rates) async {
    final from = _accounts.get(fromId);
    final to = _accounts.get(toId);
    if (from == null || to == null) return 'Счет не найден';
    if (amount <= 0) return 'Сумма должна быть больше нуля';
    if (from.balance < amount) return 'Недостаточно средств';

    double credited = amount;
    String resultDesc = 'Перевод ${from.name} -> ${to.name}';
    if (from.currency != to.currency) {
      final rate = NbrbApi.rateOf(rates, to.currency);
      if (rate == null) return 'Курс ${to.currency} недоступен (нет сети)';
      credited = amount / rate;
      resultDesc = 'Конвертация ${from.currency} -> ${to.currency}';
      _logTransaction('conversion', amount, from.currency, resultDesc,
          rate: rate);
    } else {
      _logTransaction('transfer', amount, from.currency, resultDesc);
    }

    from.balance -= amount;
    to.balance += credited;
    _accounts.put(from.id, from);
    _accounts.put(to.id, to);
    _logTransaction('deposit', credited, to.currency, resultDesc);

    state = _readState();
    return null;
  }

  // --------------------------------------------------- штрафы и бонусы

  /// Штраф за срыв Протокола Дофаминовой Стабильности.
  Future<void> applyHabitFine() async {
    final fuel = _accounts.get(Account.fuelId);
    if (fuel != null) {
      const fine = AppConstants.habitFine;
      final actual = fuel.balance >= fine ? fine : fuel.balance;
      fuel.balance -= actual;
      _accounts.put(fuel.id, fuel);
      _logTransaction('fine', actual, 'BYN',
          'Штраф: срыв Протокола Дофаминовой Стабильности');
    }
    final next = _readState();
    state = BankState(
      accounts: next.accounts,
      transactions: next.transactions,
      lastEvent: 'Штраф за срыв протокола: -${AppConstants.habitFine} BYN',
    );
  }

  /// Бонус за выполнение обеих тренировок (раз в день).
  Future<void> applyWorkoutBonus() async {
    final s = ref.read(settingsProvider);
    final today = dateKeyLocal();
    if (s.lastWorkoutBonusDay == today) return; // уже начислен

    final fuel = _accounts.get(Account.fuelId);
    if (fuel != null) {
      fuel.balance += 2;
      _accounts.put(fuel.id, fuel);
      _logTransaction('bonus', 2, 'BYN',
          'Бонус: обе тренировки выполнены');
    }
    await ref.read(settingsProvider.notifier).setWorkoutBonusDay(today);
    final next = _readState();
    state = BankState(
      accounts: next.accounts,
      transactions: next.transactions,
      lastEvent: 'Бонус за тренировки: +2 BYN',
    );
  }

  // ---------------------------------------------------------------- сброс

  Future<void> reset() async {
    await _accounts.clear();
    await _transactions.clear();
    _ensureDefaults();
    state = _readState();
  }
}

String fmtAmount(double v) => v.toStringAsFixed(2);

final bankProvider = NotifierProvider<BankController, BankState>(BankController.new);
