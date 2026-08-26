import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/habits_service.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final done = habits.habits.where((habit) => habit.doneToday()).length;
    final total = habits.habits.length;
    final progress = total == 0 ? 0.0 : done / total;

    return Scaffold(
      key: const ValueKey('more-screen'),
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _StabilityHero(
            done: done,
            total: total,
            progress: progress,
            onTap: () => context.push('/habits'),
          ),
          const SizedBox(height: 26),
          const _SectionHeading(
            title: 'Ритм и история',
            subtitle: 'Наблюдай прогресс без лишнего давления',
          ),
          const SizedBox(height: 12),
          _MoreTile(
            icon: Icons.fitness_center_rounded,
            color: AppColors.accent,
            title: 'Протокол',
            subtitle: 'Отжимания, приседания и серии выполнения',
            badge: total == 0 ? 'НЕТ ДЕЙСТВИЙ' : '$done/$total СЕГОДНЯ',
            onTap: () => context.push('/habits'),
          ),
          _MoreTile(
            icon: Icons.history_rounded,
            color: AppColors.violet,
            title: 'Журнал изменений',
            subtitle: 'Действия, важные события и история системы',
            badge: 'ХРОНОЛОГИЯ',
            onTap: () => context.push('/journal'),
          ),
          _MoreTile(
            icon: Icons.insights_rounded,
            color: AppColors.accent,
            title: 'Аналитика',
            subtitle: 'ТГК за ~1.5 года · психпортрет TikTok',
            badge: 'ИИ-ОТЧЁТЫ',
            onTap: () => context.push('/analytics'),
          ),
          const SizedBox(height: 16),
          const _SectionHeading(
            title: 'Управление',
            subtitle: 'Все технические параметры находятся в одном месте',
          ),
          const SizedBox(height: 12),
          _SettingsCard(onTap: () => context.push('/settings')),
        ],
      ),
    );
  }
}

class _StabilityHero extends StatelessWidget {
  final int done;
  final int total;
  final double progress;
  final VoidCallback onTap;

  const _StabilityHero({
    required this.done,
    required this.total,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final complete = total > 0 && done == total;
    final color = complete ? AppColors.accent : AppColors.violet;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: .2),
            AppColors.cyan.withValues(alpha: .07),
            AppColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.monitor_heart_outlined, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complete ? 'Ритм на сегодня сохранён' : 'Система поддерживает тебя',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      complete
                          ? 'Все действия выполнены — это видимый прогресс.'
                          : 'Можно начать с одного короткого действия.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '$done/$total',
                style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(value: progress, minHeight: 7, color: color),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Открыть протокол'),
          ),
        ],
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

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: color,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final VoidCallback onTap;

  const _SettingsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF27223B), Color(0xFF171E2B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.violet.withValues(alpha: .28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(Icons.tune_rounded, color: AppColors.violet),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Настройки системы', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text(
                      'Hermes AI · пенсия · тема · Vault · GitHub',
                      style: TextStyle(color: AppColors.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.violet),
            ],
          ),
        ),
      ),
    );
  }
}
