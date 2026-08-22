// Протокол тренировок: отжимания и приседания без штрафных привычек.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/habits_service.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(habitsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Протокол тренировок')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: .35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.fitness_center, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Общий стрик тренировок: ${state.trainingStreak()} дн',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final habit in state.habits) ...[
            _WorkoutCard(habit: habit),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _WorkoutCard extends ConsumerWidget {
  final HabitTracker habit;

  const _WorkoutCard({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    habit.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '${habit.currentStreak} дн',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Стрик: ${habit.currentStreak} дн · рекорд: ${habit.maxStreak} дн',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _StreakDots(habit: habit),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: habit.doneToday()
                    ? null
                    : () async {
                        await ref
                            .read(habitsProvider.notifier)
                            .markWorkout(habit.id, habit.targetReps);
                        if (context.mounted) {
                          toast(context, '${habit.name}: выполнено');
                        }
                      },
                icon: Icon(
                  habit.doneToday() ? Icons.check_circle : Icons.done,
                  size: 18,
                ),
                label: Text(
                  habit.doneToday()
                      ? 'Выполнено сегодня ✓'
                      : 'Выполнить (${habit.targetReps})',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      children: List.generate(14, (index) {
        final day = now.subtract(Duration(days: 13 - index));
        final key = dateKey(day);
        final isToday = key == today;
        final done = habit.isDoneOn(key);
        final color = done
            ? AppColors.accent
            : isToday
                ? AppColors.warning
                : AppColors.textDim.withValues(alpha: .4);
        return Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          child: done
              ? const Icon(Icons.check, size: 13)
              : isToday
                  ? const Icon(Icons.circle, size: 6)
                  : null,
        );
      }),
    );
  }
}
