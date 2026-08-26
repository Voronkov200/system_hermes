// Экран «Деньги»: локальный общий счёт, виртуальные карты и переводы.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/bank_math.dart';
import '../../services/bank_service.dart';
import '../../services/data_sync_service.dart';
import '../../services/nbrb_api.dart';
import '../../services/receipt_import_service.dart';
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

  Future<void> _deposit(
    BuildContext context,
    WidgetRef ref,
    BankState bank,
  ) async {
    if (bank.accounts.isEmpty) {
      toast(context, 'Счета пока недоступны');
      return;
    }
    final request = await showDialog<_DepositRequest>(
      context: context,
      builder: (dialogContext) => _DepositDialog(accounts: bank.accounts),
    );
    if (request == null) return;
    final error = await ref.read(bankProvider.notifier).deposit(
          accountId: request.accountId,
          amount: request.amount,
          note: request.note,
        );
    if (!context.mounted) return;
    toast(context, error ?? 'Плановый баланс пополнен');
  }

  Future<void> _importReceipts(BuildContext context, WidgetRef ref) async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return;
    final service = ref.read(receiptImportServiceProvider);
    final report = await service.importChecksFromFolder(dir);
    if (!context.mounted) return;
    toast(context, 'Чеки: ${report.summary}');
    ref.invalidate(bankProvider);
  }

  Future<void> _importPrices(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (result == null || path == null) return;
    final service = ref.read(receiptImportServiceProvider);
    final report = await service.importPricesFromJson(path);
    if (!context.mounted) return;
    toast(context, 'Цены: ${report.summary}');
  }

  /// Авто-синк чеков и цен из GitHub-каталога данных (кнопка и pull-to-refresh).
  Future<void> _syncData(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    if (!settings.syncEnabled) {
      toast(context, 'Авто-синк выключен в настройках');
      return;
    }
    final result =
        await ref.read(dataSyncServiceProvider).syncFromSettings(settings);
    if (!context.mounted) return;
    toast(context, 'Синк: ${result.summary}');
    ref.invalidate(bankProvider);
    ref.invalidate(receiptsProvider);
  }

  void _openReceipt(BuildContext context, Receipt receipt) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ReceiptSheet(receipt: receipt),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bank = ref.watch(bankProvider);
    final settings = ref.watch(settingsProvider);
    final ratesAsync = ref.watch(ratesProvider);
    final rates = ratesAsync.valueOrNull ?? NbrbApi.bundledRates;
    final totalByn = bank.totalByn(rates: rates);
    final transactions = bank.transactions.take(40).toList();
    final cardWidth =
        (MediaQuery.sizeOf(context).width * .78).clamp(260.0, 330.0).toDouble();
    final receiptsAsync = ref.watch(receiptsProvider);
    final receipts = receiptsAsync.valueOrNull ?? const <Receipt>[];
    final receiptByTxn = <String, Receipt>{
      for (final r in receipts)
        if (r.transactionId != null) r.transactionId!: r,
    };

    return Scaffold(
      key: const ValueKey('money-screen'),
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
          if (context.mounted) await _syncData(context, ref);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _TotalCard(totalByn: totalByn),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MoneyAction(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Пополнить',
                    color: AppColors.accent,
                    onTap: () => _deposit(context, ref, bank),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _MoneyAction(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Перевести',
                    color: AppColors.cyan,
                    onTap: () => _transfer(context, ref, bank, rates),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _MoneyAction(
                    icon: Icons.add_card_rounded,
                    label: 'Карта',
                    color: AppColors.violet,
                    onTap: () => _createCard(context, ref, bank),
                  ),
                ),
              ],
            ),
            if (bank.lastEvent != null) ...[
              const SizedBox(height: 10),
              _EventCard(text: bank.lastEvent!),
            ],
            const SizedBox(height: 14),
            const _LocalBankNotice(),
            const SizedBox(height: 26),
            const _SectionHeading(
              title: 'Счета',
              subtitle: 'Пенсия поступает в локальный Общий счёт',
            ),
            const SizedBox(height: 12),
            _PensionCard(
              amount: settings.pensionAmount,
              day: settings.pensionDay,
              creditedMonth: settings.lastPensionMonth,
            ),
            const SizedBox(height: 10),
            if (bank.generalAccount != null)
              _GeneralAccountCard(account: bank.generalAccount!),
            const SizedBox(height: 26),
            const _SectionHeading(
              title: 'Валютные карты',
              subtitle: 'BYN · USD · EUR · RUB — плановый баланс на телефоне',
            ),
            const SizedBox(height: 12),
            if (bank.cards.isEmpty)
              const _EmptyCards()
            else
              SizedBox(
                height: 182,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: bank.cards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => _VirtualCard(
                    account: bank.cards[index],
                    width: cardWidth,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            _RatesCard(
              rates: rates,
              isLoading: ratesAsync.isLoading,
            ),
            const SizedBox(height: 26),
            _PurchasesSection(
              receipts: receipts,
              onImportChecks: () => _importReceipts(context, ref),
              onImportPrices: () => _importPrices(context, ref),
              onSync: () => _syncData(context, ref),
              onOpen: (r) => _openReceipt(context, r),
            ),
            const SizedBox(height: 26),
            const _SectionHeading(
              title: 'История операций',
              subtitle: 'Все локальные пополнения и переводы',
            ),
            const SizedBox(height: 12),
            if (transactions.isEmpty)
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_outlined, color: AppColors.textDim),
                      SizedBox(width: 12),
                      Text(
                        'Операций пока нет',
                        style: TextStyle(color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < transactions.length; i++) ...[
                      _TransactionTile(
                        transaction: transactions[i],
                        onTap: receiptByTxn[transactions[i].id] == null
                            ? null
                            : () => _openReceipt(
                                context, receiptByTxn[transactions[i].id]!),
                      ),
                      if (i != transactions.length - 1)
                        const Divider(indent: 56, endIndent: 14),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MoneyAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MoneyAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .09),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withValues(alpha: .26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
          child: Column(
            children: [
              Icon(icon, color: color, size: 23),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _LocalBankNotice extends StatelessWidget {
  const _LocalBankNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cyan.withValues(alpha: .2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: AppColors.cyan, size: 19),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Безопасный локальный режим',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                SizedBox(height: 2),
                Text(
                  'Hermes планирует операции, но не подключается к BSB и не перемещает реальные деньги.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 10.5, height: 1.35),
                ),
              ],
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF163D35), Color(0xFF123448), Color(0xFF111925)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.accent.withValues(alpha: .32)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: .08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'ФИНАНСОВЫЙ РЕЗЕРВ',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.lock_outline_rounded, color: AppColors.textDim, size: 19),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Общий плановый капитал',
            style: TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${fmt2(totalByn)} BYN',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.currency_exchange_rounded, color: AppColors.cyan, size: 16),
              SizedBox(width: 7),
              Text(
                'Эквивалент по расчётному курсу НБРБ',
                style: TextStyle(color: AppColors.textDim, fontSize: 10.5),
              ),
            ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: AppColors.accent, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.accent, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
  final double width;

  const _VirtualCard({required this.account, required this.width});

  @override
  Widget build(BuildContext context) {
    final color = _currencyColor(account.currency);
    return Container(
      width: width,
      height: 182,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: .48),
            color.withValues(alpha: .18),
            const Color(0xFF151C27),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: .38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 25,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: color.withValues(alpha: .4)),
                ),
              ),
              const SizedBox(width: 9),
              const Icon(Icons.contactless_rounded, color: Colors.white70, size: 20),
              const Spacer(),
              Text(
                'HERMES  ${_currencySymbol(account.currency)}',
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
            '••••  ••••  ••••  3900',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'ПЛАНОВЫЙ БАЛАНС',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${fmt2(account.balance)} ${account.currency}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
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
  final VoidCallback? onTap;

  const _TransactionTile({required this.transaction, this.onTap});

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
      onTap: onTap,
      leading: Icon(
        positive ? Icons.south_west : Icons.north_east,
        color: color,
        size: 18,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.receipt_outlined, size: 15, color: AppColors.textDim),
          ],
        ],
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

class _DepositRequest {
  final String accountId;
  final double amount;
  final String note;

  const _DepositRequest({
    required this.accountId,
    required this.amount,
    required this.note,
  });
}

class _DepositDialog extends StatefulWidget {
  final List<Account> accounts;

  const _DepositDialog({required this.accounts});

  @override
  State<_DepositDialog> createState() => _DepositDialogState();
}

class _DepositDialogState extends State<_DepositDialog> {
  late String accountId;
  final amountController = TextEditingController();
  final noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final general = widget.accounts.where((a) => a.id == Account.generalId);
    accountId = general.isEmpty ? widget.accounts.first.id : general.first.id;
    amountController.addListener(_refresh);
  }

  @override
  void dispose() {
    amountController
      ..removeListener(_refresh)
      ..dispose();
    noteController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Account get account =>
      widget.accounts.firstWhere((entry) => entry.id == accountId);

  double? get amount =>
      double.tryParse(amountController.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Пополнить баланс'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Добавь уже полученные деньги в локальный учёт. '
              'Hermes не выполняет реальную банковскую операцию.',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(labelText: 'Счёт или карта'),
              items: [
                for (final item in widget.accounts)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      '${item.name} · ${item.currency}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => accountId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Сумма в ${account.currency}',
                suffixText: account.currency,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Источник или заметка',
                hintText: 'Например: перевод, наличные, заказ',
              ),
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
                    _DepositRequest(
                      accountId: accountId,
                      amount: amount!,
                      note: noteController.text.trim(),
                    ),
                  ),
          child: const Text('Пополнить'),
        ),
      ],
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

class _PurchasesSection extends StatelessWidget {
  final List<Receipt> receipts;
  final Future<void> Function() onImportChecks;
  final Future<void> Function() onImportPrices;
  final Future<void> Function() onSync;
  final void Function(Receipt) onOpen;

  const _PurchasesSection({
    required this.receipts,
    required this.onImportChecks,
    required this.onImportPrices,
    required this.onSync,
    required this.onOpen,
  });

  int get _itemsCount => receipts.fold(0, (sum, r) => sum + r.items.length);

  @override
  Widget build(BuildContext context) {
    final recent = receipts.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          title: 'Покупки',
          subtitle: 'Импорт чеков и каталога цен — часть локального учёта',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ImportButton(
                icon: Icons.receipt_long_outlined,
                label: 'Импорт чеков',
                color: AppColors.accent,
                onTap: onImportChecks,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ImportButton(
                icon: Icons.sell_outlined,
                label: 'Импорт цен',
                color: AppColors.cyan,
                onTap: onImportPrices,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onSync,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.violet,
              side: BorderSide(
                color: AppColors.violet.withValues(alpha: .5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.cloud_sync_outlined, size: 18),
            label: const Text(
              'Синхронизировать с GitHub',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          receipts.isEmpty
              ? 'Чеков нет — выбери папку с чеками'
              : 'Чеков: ${receipts.length} · позиций: $_itemsCount',
          style: const TextStyle(color: AppColors.textDim, fontSize: 11),
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(
                      Icons.receipt_outlined,
                      color: AppColors.textDim,
                      size: 18,
                    ),
                    title: Text(
                      recent[i].store,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(fmtDate(recent[i].dateTime)),
                    trailing: Text(
                      '${fmtAmount(recent[i].total)} BYN',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: () => onOpen(recent[i]),
                  ),
                  if (i != recent.length - 1)
                    const Divider(indent: 56, endIndent: 14),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ImportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onTap;

  const _ImportButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: .5)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _ReceiptSheet extends StatelessWidget {
  final Receipt receipt;

  const _ReceiptSheet({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final items = receipt.items;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.96,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  receipt.store,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (receipt.address?.isNotEmpty ?? false) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 14, color: AppColors.textDim),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    receipt.address!,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: AppColors.textDim),
              const SizedBox(width: 4),
              Text(
                fmtDateTime(receipt.dateTime),
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
          if (receipt.paymentMethod?.isNotEmpty ?? false) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.payment, size: 14, color: AppColors.textDim),
                const SizedBox(width: 4),
                Text(
                  receipt.paymentMethod!,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Итого',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${fmtAmount(receipt.total)} BYN',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          if (receipt.discount > 0) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Text(
                  'Скидка',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  '−${fmtAmount(receipt.discount)} BYN',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
          if (receipt.needsOcr) ...[
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              color: AppColors.warning.withValues(alpha: .1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.image_search, color: AppColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        receipt.items.isEmpty
                            ? 'Это скан чека. Товары не извлечены — требуется распознавание (OCR).'
                            : 'Этот чек распознан автоматически (низкая уверенность) — проверь точность данных.',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Позиции не загружены',
                style: TextStyle(color: AppColors.textDim),
              ),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${item.order}',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name),
                          if (item.quantity != 1)
                            Text(
                              '${_qty(item.quantity)} × ${fmt2(item.unitPrice)}',
                              style: const TextStyle(
                                color: AppColors.textDim,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${fmt2(item.amount)} BYN',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _qty(double qty) =>
      qty == qty.roundToDouble() ? qty.round().toString() : qty.toString();
}
