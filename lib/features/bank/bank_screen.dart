// Экран "Центральный Банк Тима": счета, курсы, конвертация, история.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/bank_service.dart';
import '../../services/nbrb_api.dart';
import '../../services/settings_service.dart';

class BankScreen extends ConsumerStatefulWidget {
  const BankScreen({super.key});

  @override
  ConsumerState<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends ConsumerState<BankScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _coinController;

  @override
  void initState() {
    super.initState();
    _coinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
  }

  @override
  void dispose() {
    _coinController.dispose();
    super.dispose();
  }

  void _onFlashChange(DateTime? flash) {
    if (flash != null && !_coinController.isAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_coinController.isAnimating) {
          _coinController.forward(from: 0);
        }
      });
    }
  }

  Future<void> _convertDialog(
      BuildContext context, WidgetRef ref, List<CurrencyRate>? rates) async {
    final s = ref.read(settingsProvider);
    final fuel = ref.read(bankProvider).byId(Account.fuelId);
    if (fuel == null) return;

    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Перевести в твердые активы'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Доступно: ${fmt2(fuel.balance)} BYN\n'
                'Курс ${s.assetsCurrency}: '
                '${NbrbApi.rateOf(rates, s.assetsCurrency)?.toStringAsFixed(2) ?? '—'} BYN'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Сумма в BYN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.replaceAll(',', '.'));
              if (v == null || v.isNaN || v.isInfinite || v <= 0) {
                Navigator.pop(ctx, null);
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Перевести'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final error = await ref
        .read(bankProvider.notifier)
        .convert(Account.fuelId, Account.assetsId, result, rates);
    if (error != null && context.mounted) toast(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final bank = ref.watch(bankProvider);
    final settings = ref.watch(settingsProvider);
    final ratesAsync = ref.watch(ratesProvider);
    final rates = ratesAsync.valueOrNull;

    _onFlashChange(bank.depositFlash);

    final fuel = bank.byId(Account.fuelId);
    final assets = bank.byId(Account.assetsId);
    final totalByn = bank.totalByn(rates: rates, assetsCurrency: settings.assetsCurrency);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Центральный Банк'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ratesProvider),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TotalCard(totalByn: totalByn),
              const SizedBox(height: 16),
              if (bank.lastEvent != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Последнее событие: ${bank.lastEvent}',
                    style: const TextStyle(color: AppColors.accent, fontSize: 12),
                  ),
                ),
              _AccountCard(account: fuel),
              const SizedBox(height: 12),
              _AccountCard(account: assets),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _convertDialog(context, ref, rates),
                      icon: const Icon(Icons.swap_horiz),
                      label: Text('Купить ${settings.assetsCurrency}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Курсы валют',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  ratesAsync.isLoading
                      ? const Text('загрузка…',
                          style: TextStyle(color: AppColors.textDim))
                      : const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 8),
              _RatesRow(asyncRates: ratesAsync),
              const SizedBox(height: 24),
              const Text('История операций',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (bank.transactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Пока нет операций',
                      style: TextStyle(color: AppColors.textDim)),
                )
              else
                ...bank.transactions.take(30).map(
                      (t) => _TransactionTile(t: t),
                    ),
            ],
          ),
          // Анимация "дождя из монет" при поступлении средств.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _coinController,
                builder: (context, _) => CustomPaint(
                  painter: CoinRainPainter(progress: _coinController.value),
                ),
              ),
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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ВСЕГО АКТИВОВ',
              style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(
            '${fmt0(totalByn)} BYN',
            style: const TextStyle(
                color: Colors.black, fontSize: 30, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Account? account;

  const _AccountCard({required this.account});

  @override
  Widget build(BuildContext context) {
    final a = account;
    if (a == null) return const SizedBox.shrink();
    final isAssets = a.id == Account.assetsId;
    final color = isAssets ? AppColors.warning : AppColors.accent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(isAssets ? Icons.vpn_key : Icons.local_fire_department,
                color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(a.currency,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                ],
              ),
            ),
            Text(
              '${a.balance.toStringAsFixed(2)} ${a.currency}',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatesRow extends ConsumerWidget {
  final AsyncValue<List<CurrencyRate>> asyncRates;

  const _RatesRow({required this.asyncRates});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncRates.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Загрузка курсов…', style: TextStyle(color: AppColors.textDim)),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Курсы недоступны: $e',
              style: const TextStyle(color: AppColors.danger)),
        ),
      ),
      data: (rates) {
        if (rates.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Данные курсов отсутствуют',
                  style: TextStyle(color: AppColors.textDim)),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: rates.map((r) {
                return Expanded(
                  child: Column(
                    children: [
                      Text('${r.code} / BYN',
                          style: const TextStyle(color: AppColors.textDim)),
                      const SizedBox(height: 4),
                      Text(r.perUnit.toStringAsFixed(2),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.accent)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction t;

  const _TransactionTile({required this.t});

  Color get _color {
    switch (t.type) {
      case 'fine':
        return AppColors.danger;
      case 'bonus':
        return AppColors.accent;
      case 'conversion':
        return AppColors.cyan;
      default:
        return AppColors.warning;
    }
  }

  String get _label {
    switch (t.type) {
      case 'deposit':
        return 'Поступление';
      case 'withdrawal':
        return 'Списание';
      case 'transfer':
        return 'Перевод';
      case 'conversion':
        return 'Конвертация';
      case 'fine':
        return 'Штраф';
      case 'bonus':
        return 'Бонус';
      default:
        return t.type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(t.description ?? '',
                    style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
              ],
            ),
          ),
          Text(
            '${t.amount >= 0 ? '+' : ''}${t.amount.toStringAsFixed(2)} ${t.currency}',
            style: TextStyle(
                color: t.type == 'fine' ? AppColors.danger : AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Художник "дождя из монет" для анимации поступления средств.
class CoinRainPainter extends CustomPainter {
  final double progress;

  CoinRainPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final paint = Paint()..color = const Color(0xFFFFD54F);
    final rng = _CoinRng(seed: 7);
    const n = 24;
    for (var i = 0; i < n; i++) {
      final x = rng.nextDouble() * size.width;
      final base = rng.nextDouble();
      final speed = 0.5 + rng.nextDouble() * 0.8;
      final y = (base + progress * speed) % 1.0 * size.height;
      final alpha = (0.25 + 0.6 * (1 - progress)) * (1 - y / size.height);
      paint.color = Color.fromRGBO(
        255,
        213,
        79,
        alpha.clamp(0.1, 0.9).toDouble(),
      );
      canvas.drawCircle(
        Offset(x, y),
        4 + rng.nextDouble() * 3,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CoinRainPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Простой детерминированный ГПСЧ для анимации.
class _CoinRng {
  int _state;

  _CoinRng({required int seed}) : _state = seed;

  double nextDouble() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}
