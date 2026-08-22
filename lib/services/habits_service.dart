// Протокол тренировок: два ежедневных действия и общий стрик.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'bank_service.dart';

const _workoutIds = ['workout_pushups', 'workout_squat'];

class HabitsState {
  final List<HabitTracker> habits;

  const HabitsState({required this.habits});

  HabitTracker? byId(String id) {
    for (final habit in habits) {
      if (habit.id == id) return habit;
    }
    return null;
  }

  /// Число дней подряд, когда выполнены обе тренировки.
  int trainingStreak() {
    final pushups = byId('workout_pushups');
    final squats = byId('workout_squat');
    if (pushups == null || squats == null) return 0;
    return pushups.currentStreak < squats.currentStreak
        ? pushups.currentStreak
        : squats.currentStreak;
  }
}

class HabitsController extends Notifier<HabitsState> {
  late final Box<HabitTracker> _box;

  @override
  HabitsState build() {
    _box = Hive.box<HabitTracker>(BoxNames.habits);
    _ensureDefaultsAndMigrate();
    _recomputeStreaks();
    return _readState();
  }

  HabitTracker _byId(String id) {
    final habit = _box.get(id);
    if (habit == null || !_workoutIds.contains(id)) {
      throw StateError('Тренировка не найдена: $id');
    }
    return habit;
  }

  void _ensureDefaultsAndMigrate() {
    // Старый пункт протокола удаляется при первом запуске новой версии.
    final obsoleteKeys = _box.keys.where((key) {
      final habit = _box.get(key);
      if (habit == null) return false;
      return habit.id == 'abstinence' ||
          habit.name.toLowerCase().contains('воздерж');
    }).toList();
    for (final key in obsoleteKeys) {
      unawaited(_box.delete(key));
    }

    if (_box.get('workout_pushups') == null) {
      unawaited(
        _box.put(
          'workout_pushups',
          HabitTracker(
            id: 'workout_pushups',
            name: 'Отжимания ×20',
            type: 'good',
            targetReps: 20,
          ),
        ),
      );
    }
    if (_box.get('workout_squat') == null) {
      unawaited(
        _box.put(
          'workout_squat',
          HabitTracker(
            id: 'workout_squat',
            name: 'Приседания ×20',
            type: 'good',
            targetReps: 20,
          ),
        ),
      );
    }
  }

  HabitsState _readState() => HabitsState(
        habits: _workoutIds
            .map((id) => _box.get(id))
            .whereType<HabitTracker>()
            .toList(),
      );

  void _recomputeStreaks() {
    final now = DateTime.now();
    for (final id in _workoutIds) {
      final habit = _box.get(id);
      if (habit == null) continue;
      var streak = 0;
      var day = now;
      if (!habit.isDoneOn(dateKey(day))) {
        day = day.subtract(const Duration(days: 1));
      }
      while (habit.isDoneOn(dateKey(day))) {
        streak++;
        day = day.subtract(const Duration(days: 1));
      }
      habit.currentStreak = streak;
      if (streak > habit.maxStreak) habit.maxStreak = streak;
      unawaited(_box.put(id, habit));
    }
  }

  Future<void> markWorkout(String id, int reps) async {
    final habit = _byId(id);
    final today = dateKey(DateTime.now());
    if (habit.isDoneOn(today)) return;

    habit.entries.add(today);
    habit.repsData.add('$today:$reps');
    await _box.put(habit.id, habit);
    _recomputeStreaks();

    final squat = _box.get('workout_squat');
    final pushups = _box.get('workout_pushups');
    if (squat?.isDoneOn(today) == true && pushups?.isDoneOn(today) == true) {
      await ref.read(bankProvider.notifier).applyWorkoutBonus();
    }
    state = _readState();
  }

  Future<void> reset() async {
    await _box.clear();
    _ensureDefaultsAndMigrate();
    _recomputeStreaks();
    state = _readState();
  }
}

final habitsProvider =
    NotifierProvider<HabitsController, HabitsState>(HabitsController.new);
