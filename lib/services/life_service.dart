// Модуль "Жизнь": RPG-механики, адаптированные под реальность.
//
// Показатели (Энергия/Настроение/Дисциплина) медленно падают со временем
// (автотики) и восстанавливаются реальными действиями. За действия и квесты
// начисляется XP -> уровни. Достижения проверяются по состоянию Банка
// и Протокола, чтобы прогресс в «Жизни» был привязан к реальности.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/life_catalog.dart';
import '../data/models.dart';
import 'bank_service.dart';
import 'habits_service.dart';

/// Состояние экрана "Жизнь" + системные уведомления.
class LifeStateEx {
  final LifeState state;
  final String? lastEvent;
  final DateTime? lastEventAt;

  const LifeStateEx({required this.state, this.lastEvent, this.lastEventAt});
}

/// Контроллер "Жизни": тики, действия, квесты, достижения.
class LifeController extends Notifier<LifeStateEx> {
  late final Box<LifeState> _box;

  @override
  LifeStateEx build() {
    _box = Hive.box<LifeState>(BoxNames.life);
    _ensureDefaults();
    final s = _applyTicks(_box.getAt(0)!);
    _box.putAt(0, s);
    _checkPassiveProgress();
    return _readState();
  }

  // ------------------------------------------------------------ инфраструктура

  LifeState _get() => _box.getAt(0)!;

  void _save(LifeState s) => _box.putAt(0, s);

  LifeStateEx _readState({String? event, DateTime? eventAt}) {
    final s = _get();
    final next = LifeState(
      energy: s.energy,
      mood: s.mood,
      discipline: s.discipline,
      xp: s.xp,
      lastTick: s.lastTick,
      startedAt: s.startedAt,
      unlockedAchievements: List.of(s.unlockedAchievements),
      currentQuestIndex: s.currentQuestIndex,
      questCompletedAt: s.questCompletedAt,
      lastActionAt: Map.of(s.lastActionAt),
      actionCounts: Map.of(s.actionCounts),
    );
    return LifeStateEx(
      state: next,
      lastEvent: event,
      lastEventAt: eventAt ?? DateTime.now(),
    );
  }

  void _ensureDefaults() {
    if (_box.isEmpty) {
      _box.add(LifeState.empty());
    }
  }

  // ------------------------------------------------------------------ тики

  /// Автоспад показателей пропорционально прошедшему времени
  /// (защита от читов: максимум maxTickGap за один раз).
  LifeState _applyTicks(LifeState s) {
    final now = DateTime.now();
    var gap = now.difference(s.lastTick);
    if (gap > AppConstants.maxTickGap) gap = AppConstants.maxTickGap;
    if (gap.inMinutes < 1) return s;

    final hours = gap.inMinutes / 60.0;
    s.energy = _clamp01(s.energy - 1.5 * hours);
    s.mood = _clamp01(s.mood - 0.8 * hours);
    s.discipline = _clamp01(s.discipline - 0.5 * hours);
    s.lastTick = now;
    return s;
  }

  double _clamp01(double v) => v.clamp(0.0, 100.0).toDouble();

  // ---------------------------------------------------------------- действия

  /// Выполнить реальное действие: изменить показатели, начислить XP,
  /// записать кулдаун и счётчик, проверить квесты/достижения.
  Future<LifeActionDef?> performAction(String actionId) async {
    final def = LifeCatalog.actionById(actionId);
    if (def == null) return null;

    final s = _get();
    final now = DateTime.now();

    // Кулдаун: действие можно выполнять только раз в cooldown.
    final last = s.lastActionAt[actionId];
    if (last != null && now.difference(last) < def.cooldown) {
      return def;
    }

    s.energy = _clamp01(s.energy + def.energyDelta);
    s.mood = _clamp01(s.mood + def.moodDelta);
    s.discipline = _clamp01(s.discipline + def.disciplineDelta);
    s.xp += def.xp;
    s.lastActionAt[actionId] = now;
    s.actionCounts[actionId] = (s.actionCounts[actionId] ?? 0) + 1;
    s.questCompletedAt = now;
    _save(s);

    _checkPassiveProgress();
    state = _readState(event: '${def.name}: +${def.xp} XP');
    return def;
  }

  // ----------------------------------------------------- квесты и достижения

  /// Проверка условий квеста по фактическим данным.
  bool _isQuestDone(LifeQuestDef q) {
    final s = _get();
    switch (q.index) {
      case 1:
        return s.actionCounts.isNotEmpty;
      case 2:
        return (s.actionCounts['walk'] ?? 0) > 0;
      case 3:
        return (s.actionCounts['study'] ?? 0) > 0;
      case 4:
        return (s.actionCounts['workout'] ?? 0) > 0;
      case 5:
        return (s.actionCounts['store'] ?? 0) > 0;
      case 6:
        return (s.actionCounts['atm'] ?? 0) > 0;
      case 7:
        return _fuelBalance() >= 50;
      case 8:
        return _assetsBalance() >= 10;
      case 9:
        return (s.actionCounts['freelance'] ?? 0) > 0;
      case 10:
        return ref.read(habitsProvider).cleanStreak() >= 7;
      case 11:
        return s.daysInSystem >= 30;
      default:
        return false;
    }
  }

  /// Награда за квесты, которые уже выполнены по факту.
  void _grantQuestRewards() {
    final s = _get();
    var changed = false;
    while (s.currentQuestIndex < LifeCatalog.quests.length) {
      final q = LifeCatalog.quests[s.currentQuestIndex];
      if (!_isQuestDone(q)) break;
      s.xp += q.xp;
      s.currentQuestIndex++;
      changed = true;
    }
    if (changed) _save(s);
  }

  /// Проверка достижений по фактам (банк, протокол, счётчики).
  void _checkAchievements() {
    final s = _get();
    var changed = false;
    for (final a in LifeCatalog.achievements) {
      if (s.unlockedAchievements.contains(a.id)) continue;
      if (!_achievementCondition(a.id)) continue;
      s.unlockedAchievements.add(a.id);
      s.xp += a.xp;
      changed = true;
    }
    if (changed) _save(s);
  }

  bool _achievementCondition(String id) {
    final s = _get();
    switch (id) {
      case 'first_action':
        return s.actionCounts.isNotEmpty;
      case 'social_3':
        return s.actionCounts.entries
            .where((e) => const ['walk', 'store', 'atm'].contains(e.key))
            .fold(0, (sum, e) => sum + e.value) >= 3;
      case 'workout_3':
        return (s.actionCounts['workout'] ?? 0) >= 3;
      case 'study_3':
        return (s.actionCounts['study'] ?? 0) >= 3;
      case 'first_freelance':
        return (s.actionCounts['freelance'] ?? 0) > 0;
      case 'xp_500':
        return s.xp >= 500;
      case 'xp_2000':
        return s.xp >= 2000;
      case 'level_5':
        return LifeCatalog.levelForXp(s.xp) >= 5;
      case 'days_7':
        return s.daysInSystem >= 7;
      case 'days_30':
        return s.daysInSystem >= 30;
      case 'clean_7':
        return ref.read(habitsProvider).cleanStreak() >= 7;
      case 'first_deposit':
        return _fuelBalance() >= 50;
      case 'first_usd':
        return _assetsBalance() >= 10;
      default:
        return false;
    }
  }

  double _fuelBalance() {
    final b = ref.read(bankProvider).generalAccount;
    return b?.balance ?? 0;
  }

  double _assetsBalance() {
    final b = ref.read(bankProvider).cardFor('USD');
    return b?.balance ?? 0;
  }

  /// Пассивная проверка: после тиков, действий, а также при открытии экрана.
  void _checkPassiveProgress() {
    _grantQuestRewards();
    _checkAchievements();
  }

  // ------------------------------------------------------------------ сброс

  Future<void> reset() async {
    await _box.clear();
    _ensureDefaults();
    state = _readState(event: 'Жизнь сброшена');
  }
}

final lifeProvider =
    NotifierProvider<LifeController, LifeStateEx>(LifeController.new);
