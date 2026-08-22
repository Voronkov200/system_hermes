// Локальный финансовый планировщик System Hermes.
//
// Интерфейс вдохновлён привычными функциями мобильного банка, но не
// подключён к БСБ Банку и не выполняет реальные банковские операции.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'bank_math.dart';
import 'nbrb_api.dart';
import 'settings_service.dart';

const supportedBankCurrencies = ['BYN', 'USD', 'EUR', 'RUB'];
const _legacyGeneralId = 'fuel';
const _legacyCardId = 'assets';

/// Состояние локального кошелька.
class BankState {
  final List<Account> accounts;
  final List<Transaction> transactions;
  final DateTime? depositFlash;
  final String? lastEvent;

  const BankState({
    required this.accounts,
    required this.transactions,
    this.depositFlash,
    this.lastEvent,
  });

  Account? byId(String id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  Account? get generalAccount => byId(Account.generalId);

  List<Account> get cards {
    final result = accounts.where((account) => account.type == 'card').toList();
    result.sort((a, b) {
      final ai = supportedBankCurrencies.indexOf(a.currency);
      final bi = supportedBankCurrencies.indexOf(b.currency);
      return ai.compareTo(bi);
    });
    return result;
  }

  Account? cardFor(String currency) => byId(Account.cardId(currency));

  double totalByn({List<CurrencyRate>? rates}) {
    double total = 0;
    for (final account in accounts) {
      final rate = NbrbApi.rateOf(rates, account.currency);
      if (rate != null) total += account.balance * rate;
    }
    return total;
  }

  double balanceFor(String currency) {
    double total = 0;
    for (final account in accounts) {
      if (account.currency == currency) total += account.balance;
    }
    return total;
  }
}

/// Управляет общим BYN-счётом, виртуальными картами и внутренними переводами.
class BankController extends Notifier<BankState> {
  late final Box<Account> _accounts;
  late final Box<Transaction> _transactions;

  @override
  BankState build() {
    _accounts = Hive.box<Account>(BoxNames.accounts);
    _transactions = Hive.box<Transaction>(BoxNames.transactions);
    _ensureDefaultsAndMigrate();
    unawaited(Future.microtask(checkPension));
    return _readState();
  }

  BankState _readState({DateTime? depositFlash, String? lastEvent}) {
    final accounts = List<Account>.of(_accounts.values)
      ..sort((a, b) {
        if (a.id == Account.generalId) return -1;
        if (b.id == Account.generalId) return 1;
        return a.name.compareTo(b.name);
      });
    final transactions = _transactions.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return BankState(
      accounts: accounts,
      transactions: transactions,
      depositFlash: depositFlash,
      lastEvent: lastEvent,
    );
  }

  Account? _storedById(String id) {
    final direct = _accounts.get(id);
    if (direct != null) return direct;
    for (final account in _accounts.values) {
      if (account.id == id) return account;
    }
    return null;
  }

  void _deleteStoredId(String id) {
    final keys = _accounts.keys
        .where((key) => key == id || _accounts.get(key)?.id == id)
        .toList();
    for (final key in keys) {
      unawaited(_accounts.delete(key));
    }
  }

  /// Переносит старые идентификаторы счетов без потери баланса.
  void _ensureDefaultsAndMigrate() {
    final legacyGeneral = _storedById(_legacyGeneralId);
    final legacyCard = _storedById(_legacyCardId);
    var general = _storedById(Account.generalId);

    if (general == null) {
      general = Account(
        id: Account.generalId,
        name: 'Общий счёт',
        currency: 'BYN',
        type: 'account',
        balance: legacyGeneral?.balance ?? 0,
      );
      unawaited(_accounts.put(general.id, general));
    } else if (legacyGeneral != null) {
      general.balance += legacyGeneral.balance;
      unawaited(_accounts.put(general.id, general));
    }

    if (legacyCard != null &&
        supportedBankCurrencies.contains(legacyCard.currency)) {
      final cardId = Account.cardId(legacyCard.currency);
      final existingCard = _storedById(cardId);
      final migratedCard = existingCard ??
          Account(
            id: cardId,
            name: 'Виртуальная карта ${legacyCard.currency}',
            currency: legacyCard.currency,
            type: 'card',
          );
      migratedCard.balance += legacyCard.balance;
      unawaited(_accounts.put(cardId, migratedCard));
    }

    _deleteStoredId(_legacyGeneralId);
    _deleteStoredId(_legacyCardId);
    _sanitizeLegacyTransactions();

    if (_transactions.isEmpty) {
      _logTransaction(
        'account_opened',
        0,
        'BYN',
        'Открыт локальный общий счёт System Hermes',
      );
    }
  }

  void _sanitizeLegacyTransactions() {
    for (final key in _transactions.keys.toList()) {
      final transaction = _transactions.get(key);
      final description = transaction?.description;
      if (transaction == null || description == null) continue;
      var updated = description
          .replaceAll('Топливо для разработки', 'Общий счёт')
          .replaceAll('Топливо разработки', 'Общий счёт')
          .replaceAll('Твердые активы', 'Виртуальная карта')
          .replaceAll('Твёрдые активы', 'Виртуальная карта');
      if (transaction.type == 'fine') {
        updated = 'Архивная корректировка старой версии';
      }
      if (updated == description) continue;
      unawaited(
        _transactions.put(
          key,
          Transaction(
            id: transaction.id,
            type: transaction.type,
            amount: transaction.amount,
            currency: transaction.currency,
            date: transaction.date,
            description: updated,
            rate: transaction.rate,
          ),
        ),
      );
    }
  }

  void _logTransaction(
    String type,
    double amount,
    String currency,
    String? description, {
    double? rate,
  }) {
    unawaited(
      _transactions.add(
        Transaction(
          id: genId(),
          type: type,
          amount: amount,
          currency: currency,
          date: DateTime.now(),
          description: description,
          rate: rate,
        ),
      ),
    );
  }

  /// Один раз за календарный месяц зачисляет официальные 390 BYN на общий
  /// счёт после выбранного дня выплаты. Повторный запуск не дублирует запись.
  Future<void> checkPension({DateTime? at}) async {
    final settings = ref.read(settingsProvider);
    final now = at ?? DateTime.now();
    final month =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final legacyMonth = '${now.year}-${now.month}';
    if (settings.lastPensionMonth == month ||
        settings.lastPensionMonth == legacyMonth ||
        now.day < settings.pensionDay) {
      return;
    }

    final general = _storedById(Account.generalId);
    if (general == null) return;
    general.balance += settings.pensionAmount;
    await _accounts.put(general.id, general);
    _logTransaction(
      'pension',
      settings.pensionAmount,
      'BYN',
      'Пенсия за $month → Общий счёт',
    );
    await ref.read(settingsProvider.notifier).setLastPensionMonth(month);

    state = _readState(
      depositFlash: DateTime.now(),
      lastEvent:
          'Пенсия зачислена: ${fmtAmount(settings.pensionAmount)} BYN',
    );
  }

  Future<String?> createVirtualCard(String currency) async {
    final code = currency.trim().toUpperCase();
    if (!supportedBankCurrencies.contains(code)) {
      return 'Валюта $code не поддерживается';
    }
    final id = Account.cardId(code);
    if (_storedById(id) != null) return 'Карта $code уже создана';

    final card = Account(
      id: id,
      name: 'Виртуальная карта $code',
      currency: code,
      type: 'card',
      balance: 0,
    );
    await _accounts.put(id, card);
    _logTransaction(
      'card_opened',
      0,
      code,
      'Создана локальная виртуальная карта $code',
    );
    state = _readState(lastEvent: 'Карта $code создана');
    return null;
  }

  /// Внутренний перевод. При разных валютах используется расчётный курс
  /// НБРБ; реальные деньги и реквизиты банка не затрагиваются.
  Future<String?> transfer({
    required String fromId,
    required String toId,
    required double amount,
    required List<CurrencyRate>? rates,
  }) async {
    final from = _storedById(fromId);
    final to = _storedById(toId);
    if (from == null || to == null) return 'Счёт или карта не найдены';
    if (from.id == to.id) return 'Выбери разные счета';
    if (!amount.isFinite || amount <= 0) {
      return 'Сумма должна быть больше нуля';
    }
    if (from.balance + 0.0000001 < amount) return 'Недостаточно средств';

    final credited = BankMath.convert(
      amount: amount,
      fromCurrency: from.currency,
      toCurrency: to.currency,
      rates: rates,
    );
    if (credited == null) {
      return 'Нет локального курса ${from.currency} → ${to.currency}';
    }

    from.balance -= amount;
    to.balance += credited;
    await _accounts.put(from.id, from);
    await _accounts.put(to.id, to);

    final description = '${from.name} → ${to.name}';
    final type = from.currency == to.currency ? 'transfer' : 'conversion';
    _logTransaction(type, -amount, from.currency, description);
    _logTransaction(type, credited, to.currency, description);
    state = _readState(
      lastEvent: 'Переведено ${fmtAmount(amount)} ${from.currency} → '
          '${fmtAmount(credited)} ${to.currency}',
    );
    return null;
  }

  Future<void> applyWorkoutBonus() async {
    final settings = ref.read(settingsProvider);
    final today = dateKeyLocal();
    if (settings.lastWorkoutBonusDay == today) return;

    final general = _storedById(Account.generalId);
    if (general != null) {
      general.balance += 2;
      await _accounts.put(general.id, general);
      _logTransaction(
        'bonus',
        2,
        'BYN',
        'Бонус: обе тренировки выполнены',
      );
    }
    await ref.read(settingsProvider.notifier).setWorkoutBonusDay(today);
    state = _readState(lastEvent: 'Бонус за тренировки: +2 BYN');
  }

  Future<void> reset() async {
    await _accounts.clear();
    await _transactions.clear();
    _ensureDefaultsAndMigrate();
    state = _readState();
  }
}

String fmtAmount(double value) => value.toStringAsFixed(2);

final bankProvider =
    NotifierProvider<BankController, BankState>(BankController.new);
