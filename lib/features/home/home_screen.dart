// Главная: спокойная сводка и один понятный следующий шаг.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/bank_service.dart';
import '../../services/habits_service.dart';
import '../../services/nbrb_api.dart';
import '../../services/settings_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bank = ref.watch(bankProvider);
    final habits = ref.watch(habitsProvider);
    final settings = ref.watch(settingsProvider);
    final ratesAsync = ref.watch(ratesProvider);
    final rates = ratesAsync.valueOrNull ?? NbrbApi.bundledRates;
    final totalByn = bank.totalByn(rates: rates);
    final trainingStreak = habits.trainingStreak();
    final completedToday = habits.habits.where((habit) => habit.doneToday()).length;

    return Scaffold(
      key: const ValueKey('home-screen'),
      appBar: AppBar(
        title: const _HermesTitle(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              tooltip: 'Настройки',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => context.push('/settings'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _FocusCard(
            trainingStreak: trainingStreak,
            completed: completedToday,
            total: habits.habits.length,
            onTap: () => context.go('/work'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.savings_outlined,
                  color: AppColors.accent,
                  value: fmt2(totalByn),
                  label: 'капитал BYN',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  icon: Icons.local_fire_department_outlined,
                  color: AppColors.warning,
                  value: '$trainingStreak',
                  label: 'дней ритма',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  icon: Icons.calendar_month_outlined,
                  color: AppColors.cyan,
                  value: fmt2(settings.pensionAmount),
                  label: 'пенсия / мес',
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const _SectionTitle(
            title: 'Основные направления',
            subtitle: 'То, что двигает самостоятельную жизнь',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 158,
            child: Row(
              children: [
                Expanded(
                  child: _AreaCard(
                    title: 'Работа',
                    subtitle: 'Учёба, проекты и Hermes',
                    icon: Icons.rocket_launch_outlined,
                    color: AppColors.accent,
                    onTap: () => context.go('/work'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AreaCard(
                    title: 'Деньги',
                    subtitle: 'Резерв, карты и переводы',
                    icon: Icons.account_balance_wallet_outlined,
                    color: AppColors.cyan,
                    onTap: () => context.go('/money'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _WideAreaTile(
            title: 'Ещё',
            subtitle: 'Протокол, журнал и управление системой',
            icon: Icons.widgets_outlined,
            color: AppColors.violet,
            onTap: () => context.go('/more'),
          ),
          const SizedBox(height: 26),
          _SectionTitle(
            title: 'Сегодня',
            subtitle: completedToday == habits.habits.length &&
                    habits.habits.isNotEmpty
                ? 'Ритм на сегодня сохранён'
                : 'Достаточно одного выполненного действия',
          ),
          const SizedBox(height: 12),
          _HabitPanel(habits: habits),
          if (rates.isNotEmpty) ...[
            const SizedBox(height: 14),
            _RatesCard(rates: rates),
          ],
        ],
      ),
    );
  }
}

class _HermesTitle extends StatelessWidget {
  const _HermesTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _IconBox(icon: Icons.terminal_rounded, color: AppColors.accent, size: 38),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HERMES',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            Text(
              'ЛИЧНАЯ СИСТЕМА',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FocusCard extends StatelessWidget {
  final int trainingStreak;
  final int completed;
  final int total;
  final VoidCallback onTap;

  const _FocusCard({
    required this.trainingStreak,
    required this.completed,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF153B35), Color(0xFF102638), Color(0xFF121A27)],
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
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan.withValues(alpha: .07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _StatusPill(
                      icon: Icons.circle,
                      text: 'СИСТЕМА ГОТОВА',
                      color: AppColors.accent,
                    ),
                    const Spacer(),
                    Text(
                      '$completed/$total сегодня',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'Один ясный шаг\nважнее идеального плана',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.45,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  trainingStreak > 0
                      ? 'У тебя уже $trainingStreak дн. устойчивого ритма. Продолжи с небольшой задачи.'
                      : 'Не нужно решать всё сразу. Выбери действие, которое можно закончить сегодня.',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                    height: 1.42,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF062018),
                  ),
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Выбрать следующий шаг'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _MetricCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textDim, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

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

class _AreaCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AreaCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBox(icon: icon, color: color, size: 42),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                  ),
                  Icon(Icons.arrow_outward_rounded, color: color, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideAreaTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _WideAreaTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _IconBox(icon: icon, color: color, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitPanel extends StatelessWidget {
  final HabitsState habits;

  const _HabitPanel({required this.habits});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/habits'),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              for (var i = 0; i < habits.habits.length; i++) ...[
                _HabitRow(habit: habits.habits[i]),
                if (i != habits.habits.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(),
                  ),
              ],
              if (habits.habits.isEmpty)
                const Text(
                  'Добавь первое действие в Протоколе',
                  style: TextStyle(color: AppColors.textDim),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  final HabitTracker habit;

  const _HabitRow({required this.habit});

  @override
  Widget build(BuildContext context) {
    final done = habit.doneToday();
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (done ? AppColors.accent : AppColors.textDim)
                .withValues(alpha: .11),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            done ? Icons.check_rounded : Icons.fitness_center_rounded,
            color: done ? AppColors.accent : AppColors.textDim,
            size: 19,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(habit.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                done ? 'Выполнено сегодня' : 'Небольшой шаг ещё доступен',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Text(
          '${habit.currentStreak} дн',
          style: TextStyle(
            color: done ? AppColors.accent : AppColors.textDim,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _RatesCard extends StatelessWidget {
  final List<CurrencyRate> rates;

  const _RatesCard({required this.rates});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.currency_exchange_rounded, color: AppColors.cyan, size: 20),
          const SizedBox(width: 10),
          for (var i = 0; i < rates.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Text(
                    rates[i].code,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    rates[i].perUnit.toStringAsFixed(2),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            if (i != rates.length - 1)
              const SizedBox(height: 24, child: VerticalDivider()),
          ],
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _IconBox({required this.icon, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(icon, color: color, size: size * .5),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _StatusPill({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 8),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }
}
