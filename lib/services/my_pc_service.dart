// Модуль "Мой ПК": виртуальный компьютер с установкой сборки Windows.
//
// Фазы: off -> bios -> setup -> reboot -> desktop. Прогресс установки
// считается по реальному времени, поэтому переживает перезапуск приложения.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';

/// Состояние виртуального ПК.
class MyPcStateView {
  final MyPcState state;
  final List<VirtualFsFile> files;

  const MyPcStateView({required this.state, required this.files});
}

/// Контроллер виртуального ПК.
class MyPcController extends Notifier<MyPcStateView> {
  late final Box<MyPcState> _box;
  late final Box<VirtualFsFile> _files;

  /// Сколько секунд длится установка Windows (для реалистичности).
  static const double setupTotalSeconds = 90;

  /// Твики, применённые к сборке (совпадают с реальной кастомизацией ISO).
  static const List<String> buildTweaks = [
    'Удалены рекламные приложения (Bing, Candy Crush и др.)',
    'Отключена телеметрия',
    'Поиск Bing отключён',
    'Только редакция Pro (6 -> 1)',
    'Образ сжат в ESD',
    'Автовход: пользователь Hermes',
  ];

  @override
  MyPcStateView build() {
    _box = Hive.box<MyPcState>(BoxNames.myPc);
    _files = Hive.box<VirtualFsFile>(BoxNames.myPcFiles);
    _seedFiles();
    var state = _box.get('pc') ?? MyPcState.empty();
    state = _advance(state, DateTime.now()) ?? state;
    _box.put('pc', state);
    return MyPcStateView(state: state, files: _files.values.toList());
  }

  // ------------------------------------------------------------- файлы

  /// Засевание виртуальной файловой системы при первом запуске.
  void _seedFiles() {
    if (_files.isNotEmpty) return;
    for (final f in VirtualFsCatalog.defaults()) {
      _files.put(f.path, f);
    }
  }

  /// Содержимое каталога [path] (папки первыми, по алфавиту).
  List<VirtualFsFile> listDir(String path) {
    final children = _files.values
        .where((f) => f.parent == path)
        .toList()
      ..sort((a, b) {
        if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return children;
  }

  /// Файл по пути (null, если не найден).
  VirtualFsFile? fileAt(String path) {
    for (final f in _files.values) {
      if (f.path == path) return f;
    }
    return null;
  }

  /// Создать/перезаписать файл (команда терминала echo > path).
  void writeFile(String path, String content) {
    final exists = fileAt(path);
    if (exists != null && exists.isFolder) return;
    _files.put(path, VirtualFsFile(path: path, content: content));
    state = MyPcStateView(state: _box.get('pc')!, files: _files.values.toList());
  }

  /// Удалить файл (команда del).
  void deleteFile(String path) {
    final f = fileAt(path);
    if (f == null) return;
    if (f.isFolder) {
      final toRemove = _files.values.where((x) =>
          x.path == path || x.path.startsWith(path + r'\')).toList();
      for (final r in toRemove) {
        _files.delete(r.path);
      }
    } else {
      _files.delete(path);
    }
    state = MyPcStateView(state: _box.get('pc')!, files: _files.values.toList());
  }

  // ------------------------------------------------------------ фазы

  /// Включение ПК: BIOS, затем автозагрузка с установочного диска.
  Future<void> powerOn() async {
    var s = _current();
    s = MyPcState(
      phase: 'bios',
      setupStage: 0,
      setupProgress: 0,
      phaseStartedAt: DateTime.now(),
      installedAt: s.installedAt,
      osName: s.osName,
      edition: s.edition,
      imageSizeGb: s.imageSizeGb,
      sourceEditions: s.sourceEditions,
      tweaks: s.tweaks,
      bootCount: s.bootCount + 1,
    );
    _save(s);
  }

  /// Выключение ПК.
  Future<void> shutdown() async {
    var s = _current();
    s = MyPcState(
      phase: 'off',
      setupStage: s.setupStage,
      setupProgress: s.setupProgress,
      installedAt: s.installedAt,
      osName: s.osName,
      edition: s.edition,
      imageSizeGb: s.imageSizeGb,
      sourceEditions: s.sourceEditions,
      tweaks: s.tweaks,
      bootCount: s.bootCount,
    );
    _save(s);
  }

  /// Перезагрузка (перезапуск всего цикла: BIOS -> установка/рабочий стол).
  Future<void> reboot() async {
    var s = _current();
    s = MyPcState(
      phase: 'bios',
      setupStage: s.installedAt != null ? 4 : s.setupStage,
      setupProgress: s.installedAt != null ? 100 : s.setupProgress,
      phaseStartedAt: DateTime.now(),
      installedAt: s.installedAt,
      osName: s.osName,
      edition: s.edition,
      imageSizeGb: s.imageSizeGb,
      sourceEditions: s.sourceEditions,
      tweaks: s.tweaks,
      bootCount: s.bootCount + 1,
    );
    _save(s);
  }

  /// Тик таймера (раз в секунду): продвигает фазы установки.
  void tick() {
    final now = DateTime.now();
    final s = _current();
    final next = _advance(s, now);
    if (next != null && !identical(next, s)) _save(next);
  }

  /// Переход между фазами по прошедшему времени.
  MyPcState? _advance(MyPcState s, DateTime now) {
    final started = s.phaseStartedAt;
    if (started == null) return s;

    switch (s.phase) {
      case 'bios':
        // 4 секунды BIOS, затем загрузка: установка (впервые) или ОС.
        if (now.difference(started).inSeconds >= 4) {
          final target = s.installedAt != null ? 'desktop' : 'setup';
          return _copyWith(s,
              phase: target,
              setupStage: target == 'setup' ? 0 : s.setupStage,
              setupProgress: target == 'setup' ? 0 : s.setupProgress,
              phaseStartedAt: now);
        }
        return s;
      case 'setup':
        final elapsed = now.difference(started).inSeconds;
        final progress =
            (elapsed / setupTotalSeconds * 100).clamp(0.0, 100.0).toDouble();
        final stage = _stageFor(progress);
        if (progress >= 100) {
          return _copyWith(s,
              phase: 'reboot',
              setupStage: 4,
              setupProgress: 100,
              phaseStartedAt: now);
        }
        return _copyWith(s, setupStage: stage, setupProgress: progress);
      case 'reboot':
        if (now.difference(started).inSeconds >= 3) {
          return _copyWith(
              s, phase: 'desktop', installedAt: now, phaseStartedAt: now);
        }
        return s;
      default:
        return s;
    }
  }

  /// Этап установки по прогрессу (как в реальной Windows).
  int _stageFor(double progress) {
    if (progress < 15) return 0; // Копирование файлов
    if (progress < 45) return 1; // Установка компонентов
    if (progress < 80) return 2; // Установка обновлений
    return 3; // Завершение
  }

  MyPcState _copyWith(
    MyPcState s, {
    required String phase,
    required int setupStage,
    required double setupProgress,
    DateTime? phaseStartedAt,
    DateTime? installedAt,
  }) =>
      MyPcState(
        phase: phase,
        setupStage: setupStage,
        setupProgress: setupProgress,
        phaseStartedAt: phaseStartedAt ?? s.phaseStartedAt,
        installedAt: installedAt ?? s.installedAt,
        osName: s.osName,
        edition: s.edition,
        imageSizeGb: s.imageSizeGb,
        sourceEditions: s.sourceEditions,
        tweaks: s.tweaks,
        bootCount: s.bootCount,
      );

  MyPcState _current() => _box.get('pc') ?? MyPcState.empty();

  void _save(MyPcState s) {
    _box.put('pc', s);
    state = MyPcStateView(state: s, files: _files.values.toList());
  }
}

final myPcProvider =
    NotifierProvider<MyPcController, MyPcStateView>(MyPcController.new);
