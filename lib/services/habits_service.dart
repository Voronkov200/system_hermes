// Модуль "Протокол Дофаминовой Стабильности": привычки и тренировки.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'bank_service.dart';
import 'mining_service.dart';
import 'settings_service.dart';

/// Состояние протокола.
class HabitsState {
  final List<HabitTracker> habits;

  /// Момент последнего штрафа (для UI-уведомления).
  final DateTime? lastPenaltyAt;
  final String? lastPenaltyText;

  const HabitsState({
    required this.habits,
    this.lastPenaltyAt,
    this.lastPenaltyText,
  });

  HabitTracker? byId(String id) {
    for (final h in habits) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// Стрик без срывов (дней).
  int cleanStreak() {
    final h = byId('abstinence');
    if (h == null) return 0;
    return h.currentStreak;
  }
}

/// Контроллер протокола: стрики, штрафы, тренировки.
class HabitsController extends Notifier<HabitsState> {
  late final Box<HabitTracker> _box;

  @override
  HabitsState build() {
    _box = Hive.box<HabitTracker>(BoxNames.habits);
    _ensureDefaults();
    _recomputeStreaks();
    return _readState();
  }

  HabitTracker _byId(String id) {
    final h = _box.get(id);
    if (h == null) {
      throw StateError('Привычка не найдена: $id');
    }
    return h;
  }

  void _ensureDefaults() {
    if (_box.isNotEmpty) return;
    _box.put('abstinence', HabitTracker(
      id: 'abstinence',
      name: 'Воздержание',
      type: 'bad',
    ));
    _box.put('workout_squat', HabitTracker(
      id: 'workout_squat',
      name: 'Приседания ×20',
      type: 'good',
      targetReps: 20,
    ));
    _box.put('workout_pushups', HabitTracker(
      id: 'workout_pushups',
      name: 'Отжимания ×20',
      type: 'good',
      targetReps: 20,
    ));
  }

  HabitsState _readState() => HabitsState(
        habits: List.of(_box.values),
      );

  /// Пересчёт стриков: для 'bad' — дни с последнего срыва,
  /// для 'good' — подряд идущие дни с выполнением.
  void _recomputeStreaks() {
    final now = DateTime.now();
    final today = dateKey(now);
    final s = ref.read(settingsProvider);

    for (final habit in List.of(_box.values)) {
      if (habit.type == 'bad') {
        final anchor = habit.lastBreakKey ?? s.protocolStart;
        int streak = 0;
        if (anchor.isNotEmpty) {
          final parsed = DateTime.tryParse(anchor);
          if (parsed != null) {
            streak = now.difference(parsed).inDays;
            if (habit.lastBreakKey == today) streak = 0;
          }
        }
        habit.currentStreak = streak < 0 ? 0 : streak;
      } else {
        var streak = 0;
        var day = now;
        if (!habit.isDoneOn(dateKey(day))) {
          day = day.subtract(const Duration(days: 1)); // сегодня ещё можно
        }
        while (habit.isDoneOn(dateKey(day))) {
          streak++;
          day = day.subtract(const Duration(days: 1));
        }
        habit.currentStreak = streak;
      }
      if (habit.currentStreak > habit.maxStreak) {
        habit.maxStreak = habit.currentStreak;
      }
      _box.put(habit.id, habit);
    }
  }

  // ------------------------------------------------------------ действия

  /// Отметить срыв вредной привычки: штраф в банке + блок фермы.
  Future<void> markBreak(String id) async {
    final habit = _byId(id);
    final today = dateKey(DateTime.now());
    if (habit.lastBreakKey == today) return; // уже отмечен

    habit.lastBreakKey = today;
    habit.currentStreak = 0;
    _box.put(habit.id, habit);

    // Штраф в Банке и блокировка майнинг-фермы на 24 часа.
    await ref.read(bankProvider.notifier).applyHabitFine();
    await ref.read(miningProvider.notifier).lockFarm(AppConstants.farmLockDuration);

    final next = _readState();
    state = HabitsState(
      habits: next.habits,
      lastPenaltyAt: DateTime.now(),
      lastPenaltyText: 'Срыв: -${fmtAmount(AppConstants.habitFine)} BYN, '
          'ферма заблокирована на 24 ч',
    );
  }

  /// Отметить выполнение тренировки (с количеством повторений).
  Future<void> markWorkout(String id, int reps) async {
    final habit = _byId(id);
    final today = dateKey(DateTime.now());
    if (habit.isDoneOn(today)) return;

    habit.entries.add(today);
    habit.repsData.add('$today:$reps');
    _box.put(habit.id, habit);
    _recomputeStreaks();

    // Бонус в банке, если обе тренировки выполнены сегодня.
    final squat = _box.get('workout_squat');
    final pushups = _box.get('workout_pushups');
    if (squat != null && pushups != null &&
        squat.isDoneOn(today) && pushups.isDoneOn(today)) {
      await ref.read(bankProvider.notifier).applyWorkoutBonus();
    }

    state = _readState();
  }

  /// Принудительный сброс статуса протокола (для тестов).
  Future<void> reset() async {
    await _box.clear();
    _ensureDefaults();
    _recomputeStreaks();
    state = _readState();
  }
}

final habitsProvider =
    NotifierProvider<HabitsController, HabitsState>(HabitsController.new);
