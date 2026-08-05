// Экран "Протокол Дофаминовой Стабильности": привычки, тренировки, стрики.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/habits_service.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final lastPenalty = habits.lastPenaltyAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Протокол Стабильности')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (lastPenalty != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      habits.lastPenaltyText ?? 'Срыв зафиксирован',
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          for (final h in habits.habits) _HabitCard(habit: h),
        ],
      ),
    );
  }
}

class _HabitCard extends ConsumerWidget {
  final HabitTracker habit;

  const _HabitCard({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBad = habit.type == 'bad';
    final accent = isBad ? AppColors.danger : AppColors.accent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isBad ? Icons.shield_outlined : Icons.fitness_center,
                    color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(habit.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text('${habit.currentStreak} дн',
                    style: TextStyle(
                        color: accent, fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isBad
                  ? 'Максимум: ${habit.maxStreak} дн • последний срыв: '
                      '${habit.lastBreakKey ?? '—'}'
                  : 'Стрик: ${habit.currentStreak} дн • рекорд: ${habit.maxStreak} дн',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _StreakDots(habit: habit),
            const SizedBox(height: 12),
            if (isBad)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: () => _confirmBreak(context, ref),
                  icon: const Icon(Icons.warning, size: 18),
                  label: const Text('Отметить срыв'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: habit.doneToday()
                      ? null
                      : () async {
                          await ref
                              .read(habitsProvider.notifier)
                              .markWorkout(habit.id, habit.targetReps);
                          if (context.mounted) {
                            toast(context,
                                '${habit.name}: выполнено! +10% хешрейта');
                          }
                        },
                  icon: Icon(
                      habit.doneToday() ? Icons.check_circle : Icons.done,
                      size: 18),
                  label: Text(habit.doneToday()
                      ? 'Выполнено сегодня ✓'
                      : 'Выполнить (${habit.targetReps})'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBreak(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Срыв протокола?'),
        content: const Text(
          'Будет применён штраф ${AppConstants.habitFine} BYN в Банке '
          'и блокировка майнинг-фермы на 24 часа. Честность — ключевая '
          'метрика системы. Подтверди:',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Не срывался'),
          ),          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да, срыв был'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(habitsProvider.notifier).markBreak(habit.id);
    if (context.mounted) {
      toast(context, 'Срыв зафиксирован. Штраф и блокировка применены.');
    }
  }
}

/// Сетка последних 14 дней: зелёный = выполнение, красный = срыв.
class _StreakDots extends StatelessWidget {
  final HabitTracker habit;

  const _StreakDots({required this.habit});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dateKey(now);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(14, (i) {
        final day = now.subtract(Duration(days: 13 - i));
        final key = dateKey(day);
        final isToday = key == today;
        final Color color;
        if (habit.type == 'bad') {
          final lastBreak = habit.lastBreakKey;
          color = lastBreak == key
              ? AppColors.danger
              : isToday
                  ? AppColors.accent
                  : AppColors.textDim.withValues(alpha: 0.4);
        } else {
          color = habit.isDoneOn(key)
              ? AppColors.accent
              : (isToday
                  ? AppColors.warning
                  : AppColors.textDim.withValues(alpha: 0.4));
        }
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          alignment: Alignment.center,
          child: isToday
              ? const Icon(Icons.circle, size: 6)
              : null,
        );
      }),
    );
  }
}
