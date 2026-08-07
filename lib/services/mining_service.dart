// Модуль "Майнинг & PC Builder": ферма, хешрейт, очки прогресса.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'habits_service.dart';

/// Состояние майнинг-фермы.
class MiningState {
  final MiningFarm farm;

  /// Текущий хешрейт с учётом множителей (0 при блокировке).
  final double hashRate;

  /// Очков в час.
  final double pointsPerHour;

  /// Список активных множителей для UI.
  final List<String> multipliers;

  /// Общий множитель.
  final double multiplier;

  const MiningState({
    required this.farm,
    required this.hashRate,
    required this.pointsPerHour,
    required this.multipliers,
    required this.multiplier,
  });

  bool get locked => farm.status == 'locked';
}

/// Контроллер фермы: сборка, установка ОС/драйверов, начисление очков.
class MiningController extends Notifier<MiningState> {
  late final Box<MiningFarm> _box;

  static const double _pointsFactor = 3.6; // очков в час на единицу мощности

  @override
  MiningState build() {
    _box = Hive.box<MiningFarm>(BoxNames.farm);
    // Пересчёт множителей при любом изменении Протокола Дофаминовой Стабильности.
    ref.listen(habitsProvider, (prev, next) {
      ref.invalidate(miningProvider);
    });
    var farm = _box.get('farm') ?? MiningFarm.empty();
    farm = _applyLockExpiry(farm);
    final rate = _computeRate(farm);
    farm = _accrue(farm, rate);
    _box.put('farm', farm);
    return _computeState(farm, rate);
  }

  // ------------------------------------------------------------ расчёты

  /// Учёт множителей от Протокола Дофаминовой Стабильности.
  /// Пересчёт запускается через ref.listen(habitsProvider) в build.
  ({double mult, List<String> labels}) _multipliers(MiningFarm farm) {
    final habits = ref.read(habitsProvider);
    double mult = 1.0;
    final labels = <String>[];

    if (farm.osInstalled == 'none') {
      return (mult: mult, labels: labels);
    }

    // Драйверы виртуального ПК: без них ферма работает на половинной мощности.
    if (!farm.driversInstalled) {
      mult *= 0.5;
      labels.add('-50% нет драйверов');
    }

    if (habits.byId('workout_squat')?.doneToday() ?? false) {
      mult += 0.10;
      labels.add('+10% приседания выполнены');
    }
    if (habits.byId('workout_pushups')?.doneToday() ?? false) {
      mult += 0.10;
      labels.add('+10% отжимания выполнены');
    }

    final clean = habits.cleanStreak();
    if (clean >= 7) {
      mult += 0.10;
      labels.add('+10% стрик 7+ дней');
    }
    if (clean >= 14) {
      mult += 0.10;
      labels.add('+10% стрик 14+ дней');
    }
    if (clean >= 30) {
      mult += 0.20;
      labels.add('+20% стрик 30+ дней');
    }

    return (mult: mult, labels: labels);
  }

  double _computeRate(MiningFarm farm) {
    final m = _multipliers(farm);
    final locked = farm.status == 'locked';
    return locked ? 0 : farm.basePower * m.mult * _pointsFactor;
  }

  MiningState _computeState(MiningFarm farm, double rate) {
    final m = _multipliers(farm);
    return MiningState(
      farm: farm,
      hashRate: farm.status == 'locked' ? 0 : farm.basePower * m.mult,
      pointsPerHour: rate,
      multipliers: m.labels,
      multiplier: m.mult,
    );
  }

  /// Разблокировка фермы по истечении таймера.
  MiningFarm _applyLockExpiry(MiningFarm farm) {
    final lock = farm.lockUntil;
    if (lock != null && DateTime.now().isAfter(lock)) {
      farm.lockUntil = null;
      return MiningFarm(
        componentIds: farm.componentIds,
        osInstalled: farm.osInstalled,
        driversInstalled: farm.driversInstalled,
        status: farm.osInstalled == 'none' ? 'offline' : 'online',
        points: farm.points,
        lastTick: farm.lastTick,
      );
    }
    return farm;
  }

  /// Начисление очков за время с последнего тика (защита от перемотки часов).
  MiningFarm _accrue(MiningFarm farm, double rate) {
    if (farm.status != 'online') {
      farm.lastTick = DateTime.now();
      return farm;
    }
    final now = DateTime.now();
    var elapsed = now.difference(farm.lastTick);
    if (elapsed > AppConstants.maxTickGap) {
      elapsed = AppConstants.maxTickGap;
    }
    if (elapsed.isNegative) elapsed = Duration.zero;
    final earned = rate * elapsed.inSeconds / 3600;
    farm.points += earned;
    farm.lastTick = now;
    return farm;
  }

  // ------------------------------------------------------------ действия

  /// Начать сборку ПК из выбранных комплектующих.
  Future<void> startBuild(List<String> componentIds) async {
    final farm = MiningFarm(
      componentIds: List.of(componentIds),
      osInstalled: 'none',
      driversInstalled: false,
      status: 'building',
      points: _box.get('farm')?.points ?? 0,
      lastTick: DateTime.now(),
    );
    _box.put('farm', farm);
    final rate = _computeRate(farm);
    state = _computeState(farm, rate);
  }

  /// Установить ОС (вызывается после симуляции терминала).
  Future<void> installOs(String os) async {
    final farm = _current();
    final next = MiningFarm(
      componentIds: farm.componentIds,
      osInstalled: os,
      driversInstalled: farm.driversInstalled,
      status: farm.status,
      points: farm.points,
      lastTick: farm.lastTick,
    );
    _box.put('farm', next);
    final rate = _computeRate(next);
    state = _computeState(next, rate);
  }

  /// Установить драйверы и запустить ферму.
  Future<void> installDrivers() async {
    final farm = _current();
    final next = MiningFarm(
      componentIds: farm.componentIds,
      osInstalled: farm.osInstalled,
      driversInstalled: true,
      status: 'online',
      points: farm.points,
      lastTick: DateTime.now(),
    );
    _box.put('farm', next);
    final rate = _computeRate(next);
    state = _computeState(next, rate);
  }

  /// Блокировка фермы (штраф за срыв протокола).
  Future<void> lockFarm(Duration duration) async {
    final farm = _current();
    final next = MiningFarm(
      componentIds: farm.componentIds,
      osInstalled: farm.osInstalled,
      driversInstalled: farm.driversInstalled,
      status: 'locked',
      lockUntil: DateTime.now().add(duration),
      points: farm.points,
      lastTick: farm.lastTick,
    );
    _box.put('farm', next);
    state = _computeState(next, 0);
  }

  MiningFarm _current() => _box.get('farm') ?? MiningFarm.empty();

  /// Сброс фермы.
  Future<void> reset() async {
    await _box.clear();
    final farm = MiningFarm.empty();
    _box.put('farm', farm);
    final rate = _computeRate(farm);
    state = _computeState(farm, rate);
  }
}

final miningProvider =
    NotifierProvider<MiningController, MiningState>(MiningController.new);
