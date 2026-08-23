// Главный экран: сводка по всем модулям системы.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/bank_service.dart';
import '../../services/habits_service.dart';
import '../../services/nbrb_api.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bank = ref.watch(bankProvider);
    final habits = ref.watch(habitsProvider);
    final ratesAsync = ref.watch(ratesProvider);
    final rates = ratesAsync.valueOrNull ?? NbrbApi.bundledRates;

    final totalByn = bank.totalByn(rates: rates);
    final trainingStreak = habits.trainingStreak();

    return Scaffold(
      key: const ValueKey('home-screen'),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: AppColors.accent),
            SizedBox(width: 8),
            Text('SYSTEM: HERMES'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusBanner(trainingStreak: trainingStreak),
          const SizedBox(height: 22),
          const _SectionTitle('Сводка'),
          const SizedBox(height: 10),
          _AreaTile(
            title: 'Работа',
            subtitle: 'Учёба, план, проекты и Hermes Agent',
            icon: Icons.work_outline,
            color: AppColors.accent,
            onTap: () => context.go('/work'),
          ),
          _AreaTile(
            title: 'Деньги',
            subtitle: 'Плановый капитал: ${fmt2(totalByn)} BYN',
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.cyan,
            onTap: () => context.go('/money'),
          ),
          _AreaTile(
            title: 'Ещё',
            subtitle: 'Протокол, журнал и настройки',
            icon: Icons.apps_outlined,
            color: AppColors.violet,
            onTap: () => context.go('/more'),
          ),
          const SizedBox(height: 12),
          const _SectionTitle('Сегодня'),
          const SizedBox(height: 10),
          _HabitStrip(habits: habits),
          if (rates.isNotEmpty) ...[
            const SizedBox(height: 14),
            _RatesCard(rates: rates),
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final int trainingStreak;

  const _StatusBanner({required this.trainingStreak});

  @override
  Widget build(BuildContext context) {
    const status = 'СИСТЕМА ГОТОВА — выбери один небольшой следующий шаг';
    const color = AppColors.accent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              status,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            'стрик $trainingStreak',
            style: const TextStyle(
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
    );
  }
}

class _AreaTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AreaTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .13),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatesCard extends StatelessWidget {
  final List<CurrencyRate> rates;

  const _RatesCard({required this.rates});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Курсы Нацбанка РБ',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: rates.map((r) {
                return Expanded(
                  child: Column(
                    children: [
                      Text(r.code,
                          style: const TextStyle(color: AppColors.textDim)),
                      Text('${r.perUnit.toStringAsFixed(2)} BYN',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitStrip extends StatelessWidget {
  final HabitsState habits;

  const _HabitStrip({required this.habits});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final h in habits.habits) {
      final done = h.doneToday();
      items.add(Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done ? AppColors.accent : const Color(0xFF1E2836)),
        ),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? AppColors.accent : AppColors.textDim,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(h.name)),
            Text('стрик ${h.currentStreak}',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
      ));
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/habits'),
      child: Column(children: items),
    );
  }
}
