// Экран «Деньги»: локальный общий счёт, виртуальные карты и переводы.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/bank_math.dart';
import '../../services/bank_service.dart';
import '../../services/nbrb_api.dart';
import '../../services/settings_service.dart';

class BankScreen extends ConsumerWidget {
  const BankScreen({super.key});

  Future<void> _createCard(
    BuildContext context,
    WidgetRef ref,
    BankState bank,
  ) async {
    final available = supportedBankCurrencies
        .where((currency) => bank.cardFor(currency) == null)
        .toList();
    if (available.isEmpty) {
      toast(context, 'Карты всех четырёх валют уже созданы');
      return;
    }

    final currency = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Новая виртуальная карта'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
              'Выбери валюту локальной карты. Реальные реквизиты БСБ здесь '
              'не создаются.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          for (final code in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, code),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _currencyColor(code).withValues(alpha: .16),
                    child: Text(
                      _currencySymbol(code),
                      style: TextStyle(
                        color: _currencyColor(code),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$code · ${_currencyName(code)}'),
                ],
              ),
            ),
        ],
      ),
    );
    if (currency == null) return;
    final error =
        await ref.read(bankProvider.notifier).createVirtualCard(currency);
    if (!context.mounted) return;
    toast(context, error ?? 'Виртуальная карта $currency создана');
  }

  Future<void> _transfer(
    BuildContext context,
    WidgetRef ref,
    BankState bank,
    List<CurrencyRate> rates,
  ) async {
    if (bank.accounts.length < 2) {
      toast(context, 'Сначала создай хотя бы одну виртуальную карту');
      return;
    }
    final request = await showDialog<_TransferRequest>(
      context: context,
      builder: (dialogContext) => _TransferDialog(
        accounts: bank.accounts,
        rates: rates,
      ),
    );
    if (request == null) return;

    final error = await ref.read(bankProvider.notifier).transfer(
          fromId: request.fromId,
          toId: request.toId,
          amount: request.amount,
          rates: rates,
        );
    if (!context.mounted) return;
    toast(context, error ?? 'Внутренний перевод выполнен');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bank = ref.watch(bankProvider);
    final settings = ref.watch(settingsProvider);
    final ratesAsync = ref.watch(ratesProvider);
    final rates = ratesAsync.valueOrNull ?? NbrbApi.bundledRates;
    final totalByn = bank.totalByn(rates: rates);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Деньги'),
        actions: [
          IconButton(
            tooltip: 'Обновить курсы',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ratesProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ratesProvider);
          await ref.read(bankProvider.notifier).checkPension();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const _LocalBankNotice(),
            const SizedBox(height: 12),
            _TotalCard(totalByn: totalByn),
            const SizedBox(height: 12),
            if (bank.lastEvent != null)
              _EventCard(text: bank.lastEvent!),
            _PensionCard(
              amount: settings.pensionAmount,
              day: settings.pensionDay,
              creditedMonth: settings.lastPensionMonth,
            ),
            const SizedBox(height: 12),
            if (bank.generalAccount != null)
              _GeneralAccountCard(account: bank.generalAccount!),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _createCard(context, ref, bank),
                    icon: const Icon(Icons.add_card),
                    label: const Text('Создать карту'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _transfer(context, ref, bank, rates),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Перевести'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Виртуальные карты',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Карты хранят локальный плановый баланс на этом телефоне.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (bank.cards.isEmpty)
              const _EmptyCards()
            else
              for (final card in bank.cards) ...[
                _VirtualCard(account: card),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 12),
            _RatesCard(
              rates: rates,
              isLoading: ratesAsync.isLoading,
            ),
            const SizedBox(height: 24),
            const Text(
              'История операций',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (bank.transactions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Операций пока нет',
                    style: TextStyle(color: AppColors.textDim),
                  ),
                ),
              )
            else
              for (final transaction in bank.transactions.take(40))
                _TransactionTile(transaction: transaction),
          ],
        ),
      ),
    );
  }
}

class _LocalBankNotice extends StatelessWidget {
  const _LocalBankNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cyan.withValues(alpha: .32)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: AppColors.cyan, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Локальный финансовый планировщик. Он повторяет нужные тебе '
              'сценарии BSB, но не подключён к банку и не перемещает реальные '
              'деньги.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final double totalByn;

  const _TotalCard({required this.totalByn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00E5A0), Color(0xFF00B8D4)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ПЛАНОВЫЙ КАПИТАЛ',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${fmt2(totalByn)} BYN',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            'Эквивалент по расчётному курсу НБРБ',
            style: TextStyle(color: Colors.black54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final String text;

  const _EventCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.accent, fontSize: 12),
      ),
    );
  }
}

class _PensionCard extends StatelessWidget {
  final double amount;
  final int day;
  final String creditedMonth;

  const _PensionCard({
    required this.amount,
    required this.day,
    required this.creditedMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x1A00E5A0),
          child: Icon(Icons.calendar_month, color: AppColors.accent),
        ),
        title: Text(
          'Официальная пенсия: ${fmt2(amount)} BYN',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Автозачисление на Общий счёт после $day-го числа'
          '${creditedMonth.isEmpty ? '' : ' · учтён $creditedMonth'}',
        ),
      ),
    );
  }
}

class _GeneralAccountCard extends StatelessWidget {
  final Account account;

  const _GeneralAccountCard({required this.account});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet, color: AppColors.accent),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Общий счёт',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Источник пенсии и переводов',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '${fmt2(account.balance)} BYN',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VirtualCard extends StatelessWidget {
  final Account account;

  const _VirtualCard({required this.account});

  @override
  Widget build(BuildContext context) {
    final color = _currencyColor(account.currency);
    return Container(
      height: 168,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: .86),
            color.withValues(alpha: .42),
            AppColors.surfaceAlt,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.contactless, color: Colors.white),
              const Spacer(),
              Text(
                'HERMES · ${account.currency}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'ЛОКАЛЬНАЯ ВИРТУАЛЬНАЯ КАРТА',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${fmt2(account.balance)} ${account.currency}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCards extends StatelessWidget {
  const _EmptyCards();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.add_card, color: AppColors.textDim),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Создай карту BYN, USD, EUR или RUB. После этого между '
                'Общим счётом и картами станут доступны переводы.',
                style: TextStyle(color: AppColors.textDim, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatesCard extends StatelessWidget {
  final List<CurrencyRate> rates;
  final bool isLoading;

  const _RatesCard({required this.rates, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final date = rates.isEmpty ? null : rates.first.date;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Расчётные курсы НБРБ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              date == null
                  ? 'Данные отсутствуют'
                  : 'Снимок от ${fmtDate(date)} · курс BSB может отличаться',
              style: const TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final rate in rates)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          rate.code,
                          style: TextStyle(
                            color: _currencyColor(rate.code),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          rate.perUnit.toStringAsFixed(4),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;

  const _TransactionTile({required this.transaction});

  String get _label {
    switch (transaction.type) {
      case 'pension':
        return 'Пенсия';
      case 'transfer':
        return 'Внутренний перевод';
      case 'conversion':
        return 'Конвертация';
      case 'fine':
        return 'Штраф';
      case 'bonus':
        return 'Бонус';
      case 'card_opened':
        return 'Новая карта';
      case 'account_opened':
        return 'Открытие счёта';
      case 'deposit':
        return 'Поступление';
      default:
        return transaction.type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final positive = transaction.amount >= 0;
    final color = transaction.amount == 0
        ? AppColors.textDim
        : positive
            ? AppColors.accent
            : AppColors.danger;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        positive ? Icons.south_west : Icons.north_east,
        color: color,
        size: 18,
      ),
      title: Text(
        _label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${transaction.description ?? ''} · ${fmtDate(transaction.date)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${transaction.amount > 0 ? '+' : ''}'
        '${transaction.amount.toStringAsFixed(2)} ${transaction.currency}',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TransferRequest {
  final String fromId;
  final String toId;
  final double amount;

  const _TransferRequest({
    required this.fromId,
    required this.toId,
    required this.amount,
  });
}

class _TransferDialog extends StatefulWidget {
  final List<Account> accounts;
  final List<CurrencyRate> rates;

  const _TransferDialog({required this.accounts, required this.rates});

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  late String fromId;
  late String toId;
  final amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final general = widget.accounts.where((a) => a.id == Account.generalId);
    fromId = general.isEmpty ? widget.accounts.first.id : general.first.id;
    toId = widget.accounts.firstWhere((a) => a.id != fromId).id;
    amountController.addListener(_refresh);
  }

  @override
  void dispose() {
    amountController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Account get from => widget.accounts.firstWhere((a) => a.id == fromId);
  Account get to => widget.accounts.firstWhere((a) => a.id == toId);

  double? get amount =>
      double.tryParse(amountController.text.trim().replaceAll(',', '.'));

  double? get preview {
    final value = amount;
    if (value == null) return null;
    return BankMath.convert(
      amount: value,
      fromCurrency: from.currency,
      toCurrency: to.currency,
      rates: widget.rates,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Внутренний перевод'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('from-$fromId'),
              initialValue: fromId,
              decoration: const InputDecoration(labelText: 'Откуда'),
              items: [
                for (final account in widget.accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.name} · ${fmt2(account.balance)} '
                      '${account.currency}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  fromId = value;
                  if (toId == fromId) {
                    toId =
                        widget.accounts.firstWhere((a) => a.id != fromId).id;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('to-$fromId-$toId'),
              initialValue: toId,
              decoration: const InputDecoration(labelText: 'Куда'),
              items: [
                for (final account in widget.accounts)
                  if (account.id != fromId)
                    DropdownMenuItem(
                      value: account.id,
                      child: Text(
                        '${account.name} · ${account.currency}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => toId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Сумма в ${from.currency}',
                helperText: 'Доступно: ${fmt2(from.balance)} ${from.currency}',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                preview == null
                    ? 'Введи сумму'
                    : 'Будет зачислено ≈ ${fmt2(preview!)} ${to.currency}',
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Комиссия в локальном учёте: 0. Реальный курс и комиссия банка '
              'могут отличаться.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: amount == null || amount! <= 0
              ? null
              : () => Navigator.pop(
                    context,
                    _TransferRequest(
                      fromId: fromId,
                      toId: toId,
                      amount: amount!,
                    ),
                  ),
          child: const Text('Перевести'),
        ),
      ],
    );
  }
}

Color _currencyColor(String code) {
  switch (code) {
    case 'USD':
      return AppColors.cyan;
    case 'EUR':
      return AppColors.violet;
    case 'RUB':
      return AppColors.warning;
    case 'BYN':
    default:
      return AppColors.accent;
  }
}

String _currencySymbol(String code) {
  switch (code) {
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'RUB':
      return '₽';
    case 'BYN':
    default:
      return 'Br';
  }
}

String _currencyName(String code) {
  switch (code) {
    case 'USD':
      return 'доллар США';
    case 'EUR':
      return 'евро';
    case 'RUB':
      return 'российский рубль';
    case 'BYN':
    default:
      return 'белорусский рубль';
  }
}
