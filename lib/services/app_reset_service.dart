// Полный сброс локальных данных System Hermes.
//
// Внешний Obsidian Vault намеренно не удаляется: очищается только сохранённая
// ссылка на него. Папка SystemHermes и внутренние кэши принадлежат приложению.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'agent/file_tools.dart';
import 'journal_service.dart';
import 'plan/docs_service.dart';
import 'settings_service.dart';
import 'study/study_service.dart';
import 'tasks_service.dart';

class AppResetService {
  final Ref ref;

  AppResetService(this.ref);

  Future<void> resetAll() async {
    await _clearBox<Account>(BoxNames.accounts);
    await _clearBox<Transaction>(BoxNames.transactions);
    await _clearBox<HabitTracker>(BoxNames.habits);
    await _clearBox<ChatMessage>(BoxNames.chat);
    await _clearBox<HermesTask>(BoxNames.tasks);
    await _clearBox<JournalEntry>(BoxNames.journal);
    await _clearBox<SourceDoc>(BoxNames.docs);
    await _clearBox<StudySubject>(BoxNames.study);
    await _clearBox<StudyParagraph>(BoxNames.studyParagraphs);

    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.clear();
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    await preferences.setString(PrefKeys.pensionResetMonth, month);
    await _deleteHermesFiles();
    await _clearAppCache();
    await _deleteVoiceRecordings();
  }

  Future<void> _clearBox<T>(String name) async {
    try {
      await Hive.box<T>(name).clear();
    } catch (_) {
      // Бокс может быть ещё не открыт в изолированном тесте. В обычном
      // запуске main.dart открывает все боксы до появления настроек.
    }
  }

  Future<void> _deleteHermesFiles() async {
    try {
      final root = await FileTools.root();
      final normalized = root.absolute.path.replaceAll('\\', '/');
      final owned = normalized.endsWith('/SystemHermes') ||
          normalized.endsWith('/HermesFiles');
      if (owned && await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _clearAppCache() async {
    for (final loader in [getTemporaryDirectory, getApplicationCacheDirectory]) {
      try {
        final directory = await loader();
        if (!await directory.exists()) continue;
        await for (final entity in directory.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  Future<void> _deleteVoiceRecordings() async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      await for (final entity in documents.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (RegExp(r'^voice_\d+\.m4a$').hasMatch(name)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

final appResetServiceProvider = Provider<AppResetService>(AppResetService.new);
