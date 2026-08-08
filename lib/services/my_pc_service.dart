// Модуль "Мой ПК": виртуальный компьютер с установкой сборки Windows.
//
// Фазы: off -> post -> (bios_setup) -> setup | desktop -> reboot -> post...
// Прогресс установки считается по реальному времени, поэтому переживает
// перезапуск приложения. Железо читается из майнинг-фермы (единый источник).

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'journal_service.dart';

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

  /// Сколько секунд длится POST.
  static const int postSeconds = 2;

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

  /// Создать/перезаписать файл.
  void writeFile(String path, String content) {
    final exists = fileAt(path);
    if (exists != null && exists.isFolder) return;
    _files.put(path, VirtualFsFile(path: path, content: content));
    _emit();
  }

  /// Создать папку.
  String? createFolder(String path) {
    final exists = fileAt(path);
    if (exists != null) return 'Папка уже существует.';
    _files.put(path, VirtualFsFile(path: path, isFolder: true));
    _emit();
    return null;
  }

  /// Переименовать файл/папку.
  String? renameFile(String path, String newName) {
    final f = fileAt(path);
    if (f == null) return 'Файл не найден.';
    if (newName.trim().isEmpty) return 'Имя не может быть пустым.';
    final parent = f.parent;
    final newPath = parent.isEmpty ? newName : '$parent\\$newName';
    if (fileAt(newPath) != null) return 'Объект с таким именем уже существует.';
    _files.delete(path);
    if (f.isFolder) {
      // Перемещаем всё содержимое папки.
      final children = _files.values
          .where((x) => x.path.startsWith(path + r'\'))
          .toList();
      for (final c in children) {
        _files.delete(c.path);
        final rel = c.path.substring(path.length);
        _files.put(
          newPath + rel,
          VirtualFsFile(
            path: newPath + rel,
            content: c.content,
            isFolder: c.isFolder,
            originalPath: c.originalPath,
          ),
        );
      }
    }
    _files.put(
      newPath,
      VirtualFsFile(
        path: newPath,
        content: f.content,
        isFolder: f.isFolder,
        originalPath: f.originalPath,
      ),
    );
    _emit();
    return null;
  }

  /// Переместить файл/папку в Корзину.
  void moveToRecycle(String path) {
    final f = fileAt(path);
    if (f == null || f.recycled) return;
    if (f.isFolder) {
      final children = _files.values
          .where((x) => x.path == path || x.path.startsWith(path + r'\'))
          .toList();
      for (final c in children) {
        _files.delete(c.path);
        final name = c.path == path
            ? f.name
            : r'$Recycle.Bin' + c.path.substring(path.length);
        _files.put(
          c.path,
          VirtualFsFile(
            path: r'C:\$Recycle.Bin\' + name,
            content: c.content,
            isFolder: c.isFolder,
            originalPath: c.path,
          ),
        );
      }
    } else {
      _files.delete(path);
      _files.put(
        r'C:\$Recycle.Bin\' + f.name,
        VirtualFsFile(
          path: r'C:\$Recycle.Bin\' + f.name,
          content: f.content,
          isFolder: false,
          originalPath: path,
        ),
      );
    }
    _emit();
  }

  /// Восстановить файл из Корзины на прежнее место.
  String? restoreFromRecycle(String path) {
    final f = fileAt(path);
    if (f == null || !f.recycled) return 'Файл не в Корзине.';
    final target = f.originalPath!;
    if (fileAt(target) != null) return 'На месте уже есть объект: $target';
    _files.delete(path);
    _files.put(
      target,
      VirtualFsFile(
        path: target,
        content: f.content,
        isFolder: f.isFolder,
      ),
    );
    _emit();
    return null;
  }

  /// Удалить файл из Корзины безвозвратно.
  void purgeFromRecycle(String path) {
    final f = fileAt(path);
    if (f == null || !f.recycled) return;
    if (f.isFolder) {
      final toRemove = _files.values
          .where((x) => x.path.startsWith(path + r'\'))
          .toList();
      for (final r in toRemove) {
        _files.delete(r.path);
      }
    }
    _files.delete(path);
    _emit();
  }

  /// Параметры файла (размер, дата создания, тип).
  ({String size, String createdAt}) propsOf(String path) {
    final f = fileAt(path);
    if (f == null) return (size: '—', createdAt: '—');
    if (f.isFolder) {
      final count = listDir(path).length;
      return (
        size: '$count объектов',
        createdAt: 'с системным образом'
      );
    }
    final bytes = f.content.length * 2;
    final size = bytes < 1024
        ? '$bytes Б'
        : bytes < 1024 * 1024
            ? '${(bytes / 1024).toStringAsFixed(1)} КБ'
            : '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
    return (size: size, createdAt: 'с системным образом');
  }

  // ------------------------------------------------------------ персонализация

  /// Выбор обоев рабочего стола.
  Future<void> setWallpaper(String id) async {
    var s = _current();
    s = _copyWith(s, wallpaperId: id);
    _save(s);
  }

  /// Смена имени компьютера (валидация Windows: A-Z a-z 0-9 - _).
  Future<void> setComputerName(String name) async {
    var s = _current();
    final clean = name
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\-_]'), '');
    final finalName = clean.length > 15 ? clean.substring(0, 15) : clean;
    s = _copyWith(s, computerName: finalName.isEmpty ? 'HERMES-01' : finalName);
    _save(s);
  }

  /// Смена темы панели задач (dark | light | blue).
  Future<void> setTaskbarTheme(String theme) async {
    var s = _current();
    s = _copyWith(s, taskbarTheme: theme);
    _save(s);
  }

  /// Автоскрытие нижней панели приложения (как панель задач в Windows).
  Future<void> setBottomBarHidden(bool hidden) async {
    var s = _current();
    s = _copyWith(s, bottomBarHidden: hidden);
    _save(s);
  }

  /// Приоритет загрузки BIOS: dvd | hdd | usb.
  Future<void> setBootPriority(String priority) async {
    var s = _current();
    s = _copyWith(s, bootPriority: priority);
    _save(s);
  }

  // ------------------------------------------------------------ фазы

  /// Включение ПК: POST, затем автозагрузка с выбранного носителя.
  Future<void> powerOn() async {
    final s = _current();
    if (s.phase != 'off') return; // защита от повторных тапов
    final next = MyPcState(
      phase: 'post',
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
      wallpaperId: s.wallpaperId,
      computerName: s.computerName,
      taskbarTheme: s.taskbarTheme,
      bottomBarHidden: s.bottomBarHidden,
      bootPriority: s.bootPriority,
    );
    _save(next);
    HapticFeedback.lightImpact();
    _log('Включение ПК (включений: ${next.bootCount})');
  }

  /// Выключение ПК.
  Future<void> shutdown() async {
    final s = _current();
    if (s.phase == 'off') return;
    final next = MyPcState(
      phase: 'off',
      setupStage: s.setupStage,
      setupProgress: s.setupProgress,
      phaseStartedAt: null,
      installedAt: s.installedAt,
      osName: s.osName,
      edition: s.edition,
      imageSizeGb: s.imageSizeGb,
      sourceEditions: s.sourceEditions,
      tweaks: s.tweaks,
      bootCount: s.bootCount,
      wallpaperId: s.wallpaperId,
      computerName: s.computerName,
      taskbarTheme: s.taskbarTheme,
      bottomBarHidden: s.bottomBarHidden,
      bootPriority: s.bootPriority,
    );
    _save(next);
    _log('Выключение ПК');
  }

  /// Перезагрузка (перезапуск всего цикла: POST -> ОС).
  Future<void> reboot() async {
    final s = _current();
    if (s.phase == 'off') return;
    final next = MyPcState(
      phase: 'post',
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
      wallpaperId: s.wallpaperId,
      computerName: s.computerName,
      taskbarTheme: s.taskbarTheme,
      bottomBarHidden: s.bottomBarHidden,
      bootPriority: s.bootPriority,
    );
    _save(next);
    _log('Перезагрузка ПК');
  }

  /// Вход в BIOS Setup (во время POST).
  Future<void> enterBiosSetup() async {
    final s = _current();
    if (s.phase != 'post') return;
    final next = MyPcState(
      phase: 'bios_setup',
      setupStage: s.setupStage,
      setupProgress: s.setupProgress,
      phaseStartedAt: s.phaseStartedAt,
      installedAt: s.installedAt,
      osName: s.osName,
      edition: s.edition,
      imageSizeGb: s.imageSizeGb,
      sourceEditions: s.sourceEditions,
      tweaks: s.tweaks,
      bootCount: s.bootCount,
      wallpaperId: s.wallpaperId,
      computerName: s.computerName,
      taskbarTheme: s.taskbarTheme,
      bottomBarHidden: s.bottomBarHidden,
      bootPriority: s.bootPriority,
    );
    _save(next);
  }

  /// Выход из BIOS Setup: сохранить (save) или без сохранения.
  Future<void> exitBiosSetup({bool save = true}) async {
    final s = _current();
    if (s.phase != 'bios_setup') return;
    final next = MyPcState(
      phase: 'post',
      setupStage: s.setupStage,
      setupProgress: s.setupProgress,
      phaseStartedAt: DateTime.now(),
      installedAt: s.installedAt,
      osName: s.osName,
      edition: s.edition,
      imageSizeGb: s.imageSizeGb,
      sourceEditions: s.sourceEditions,
      tweaks: s.tweaks,
      bootCount: s.bootCount,
      wallpaperId: s.wallpaperId,
      computerName: s.computerName,
      taskbarTheme: s.taskbarTheme,
      bottomBarHidden: s.bottomBarHidden,
      bootPriority: s.bootPriority,
    );
    _save(next);
    _log(save ? 'BIOS: сохранено и перезагрузка' : 'BIOS: выход без сохранения');
  }

  /// Тик таймера (раз в секунду): продвигает фазы.
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
      case 'post':
        // POST короткий: 2 секунды, затем загрузка с выбранного носителя.
        if (now.difference(started).inSeconds >= postSeconds) {
          final fromDvd = s.bootPriority == 'dvd' || s.bootPriority == 'usb';
          final firstInstall = fromDvd && s.installedAt == null;
          if (firstInstall) {
            _log('POST OK — загрузка с установочного носителя');
            return _copyWith(s,
                phase: 'setup',
                setupStage: 0,
                setupProgress: 0,
                phaseStartedAt: now);
          }
          if (s.installedAt == null) {
            // Нет системы и выбран HDD — вернёмся в POST через BIOS.
            return _copyWith(s, phase: 'bios_setup', phaseStartedAt: now);
          }
          _log('POST OK — загрузка с жёсткого диска');
          return _copyWith(s,
              phase: 'desktop',
              setupStage: 4,
              setupProgress: 100,
              phaseStartedAt: now);
        }
        return s;
      case 'setup':
        final elapsed = now.difference(started).inSeconds;
        final progress =
            (elapsed / setupTotalSeconds * 100).clamp(0.0, 100.0).toDouble();
        final stage = _stageFor(progress);
        if (progress >= 100) {
          _log('Установка Windows завершена');
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
              s, phase: 'post', installedAt: now, phaseStartedAt: now);
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

  // --------------------------------------------------------------- журнал

  void _log(String title) {
    try {
      ref.read(journalProvider.notifier).add(
            type: 'system',
            source: 'pc',
            title: title,
            text: '',
          );
    } catch (_) {}
  }

  // ----------------------------------------------------------- служебное

  MyPcState _copyWith(
    MyPcState s, {
    String? phase,
    int? setupStage,
    double? setupProgress,
    DateTime? phaseStartedAt,
    DateTime? installedAt,
    String? wallpaperId,
    String? computerName,
    String? taskbarTheme,
    bool? bottomBarHidden,
    String? bootPriority,
  }) =>
      MyPcState(
        phase: phase ?? s.phase,
        setupStage: setupStage ?? s.setupStage,
        setupProgress: setupProgress ?? s.setupProgress,
        phaseStartedAt: phaseStartedAt ?? s.phaseStartedAt,
        installedAt: installedAt ?? s.installedAt,
        osName: s.osName,
        edition: s.edition,
        imageSizeGb: s.imageSizeGb,
        sourceEditions: s.sourceEditions,
        tweaks: s.tweaks,
        bootCount: s.bootCount,
        wallpaperId: wallpaperId ?? s.wallpaperId,
        computerName: computerName ?? s.computerName,
        taskbarTheme: taskbarTheme ?? s.taskbarTheme,
        bottomBarHidden: bottomBarHidden ?? s.bottomBarHidden,
        bootPriority: bootPriority ?? s.bootPriority,
      );

  MyPcState _current() => _box.get('pc') ?? MyPcState.empty();

  void _emit() {
    state = MyPcStateView(state: _box.get('pc')!, files: _files.values.toList());
  }

  void _save(MyPcState s) {
    _box.put('pc', s);
    _emit();
  }
}

final myPcProvider =
    NotifierProvider<MyPcController, MyPcStateView>(MyPcController.new);
