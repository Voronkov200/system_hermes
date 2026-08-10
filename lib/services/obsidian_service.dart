// Модуль "Obsidian Sync Engine": доступ к Vault, watcher, заметки.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watcher/watcher.dart';

import '../data/models.dart';
import 'settings_service.dart';

/// Состояние Obsidian-модуля.
class ObsidianState {
  final String? vaultPath;
  final List<ObsidianNote> notes; // метаданные (content пуст)
  final bool watching;
  final bool loading;
  final String? error;

  const ObsidianState({
    this.vaultPath,
    this.notes = const [],
    this.watching = false,
    this.loading = false,
    this.error,
  });

  ObsidianState copyWith({
    String? vaultPath,
    List<ObsidianNote>? notes,
    bool? watching,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return ObsidianState(
      vaultPath: vaultPath ?? this.vaultPath,
      notes: notes ?? this.notes,
      watching: watching ?? this.watching,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Контроллер Obsidian: выбор папки, сканирование, чтение/запись, watcher.
class ObsidianController extends Notifier<ObsidianState> {
  StreamSubscription<WatchEvent>? _sub;
  Timer? _debounce;
  bool _watching = false;

  @override
  ObsidianState build() {
    final path = ref.watch(settingsProvider).vaultPath;
    ref.onDispose(() {
      _sub?.cancel();
      _debounce?.cancel();
    });
    _watching = false;
    if (path.isNotEmpty) {
      _startWatcher(path);
      Future.microtask(refresh);
    }
    return ObsidianState(
      vaultPath: path.isEmpty ? null : path,
      watching: _watching,
    );
  }

  // ------------------------------------------------------------ watcher

  /// Отслеживание изменений в Vault в реальном времени.
  void _startWatcher(String path) {
    _sub?.cancel();
    _watching = false;
    try {
      final watcher = DirectoryWatcher(path);
      _sub = watcher.events.listen((event) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 600), refresh);
      });
      _watching = true;
    } catch (_) {
      _watching = false;
    }
  }

  void _emit() {
    state = state.copyWith(watching: _watching);
  }

  // --------------------------------------------------------------- vault

  /// Выбор папки Vault через File Picker (SAF на Android).
  Future<void> pickVault() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Выберите папку Obsidian Vault',
    );
    if (path == null || path.isEmpty) return;
    await ref.read(settingsProvider.notifier).setVaultPath(path);
    // build() перезапустится через ref.watch(settingsProvider)
    if (state.vaultPath == path) {
      _startWatcher(path);
      _emit();
    }
    await refresh();
  }

  /// Сканирование Vault: список .md файлов (до глубины 4).
  Future<void> refresh() async {
    final path = state.vaultPath;
    if (path == null) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        state = state.copyWith(
          loading: false,
          error: 'Папка Vault недоступна',
        );
        return;
      }
      final notes = <ObsidianNote>[];
      await _walk(dir, notes, 0);
      notes.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      state = state.copyWith(notes: notes, loading: false);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Ошибка сканирования: $e',
      );
    }
  }

  Future<void> _walk(Directory dir, List<ObsidianNote> acc, int depth) async {
    if (depth > 4) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name == '.obsidian' || name == '.git' || name.startsWith('.')) {
          continue;
        }
        await _walk(entity, acc, depth + 1);
      } else if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        try {
          final stat = await entity.stat();
          final title = entity.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll('.md', '');
          acc.add(ObsidianNote(
            path: entity.path,
            title: title,
            content: '',
            modifiedAt: stat.modified,
          ));
        } catch (_) {
          // пропускаем файлы, которые не читаются
        }
      }
    }
  }

  // -------------------------------------------------------------- файлы

  /// Чтение содержимого заметки.
  Future<ObsidianNote?> readNote(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      return ObsidianNote(
        path: path,
        title: path.split(Platform.pathSeparator).last.replaceAll('.md', ''),
        content: await file.readAsString(),
        modifiedAt: stat.modified,
      );
    } catch (_) {
      return null;
    }
  }

  /// Создание новой заметки в Vault.
  Future<String?> createNote(String title, String content) async {
    final path = state.vaultPath;
    if (path == null) return 'Сначала выберите папку Vault в настройках';
    final safeTitle = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    if (safeTitle.isEmpty) return 'Пустое название заметки';
    try {
      final file = File('$path${Platform.pathSeparator}$safeTitle.md');
      await file.writeAsString(content);
      await refresh();
      return null;
    } catch (e) {
      return 'Ошибка записи: $e';
    }
  }

  /// Сохранение изменений в существующей заметке.
  Future<String?> editNote(String path, String content) async {
    try {
      final file = File(path);
      await file.writeAsString(content);
      await refresh();
      return null;
    } catch (e) {
      return 'Ошибка записи: $e';
    }
  }
}

final obsidianProvider =
    NotifierProvider<ObsidianController, ObsidianState>(ObsidianController.new);
