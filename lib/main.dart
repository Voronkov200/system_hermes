// Точка входа: инициализация Hive, адаптеров и SharedPreferences.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/adapters.dart';
import 'data/models.dart';
import 'services/settings_service.dart';
import 'services/tasks_service.dart';
import 'services/journal_service.dart';
import 'services/plan/docs_service.dart';
import 'services/study/study_service.dart';

/// Менеджер шрифтов PDF живёт всё время работы приложения. На Android
/// официальные школьные PDF часто ссылаются на шрифты, которых нет внутри
/// самого файла (особенно математические/символьные гарнитуры). PDFium без
/// системных путей может тогда показать обычный текст, но потерять формулы.
final hermesPdfFontManager = PdfFontManager(resolvers: const []);

Future<void> _initializePdfEngine() async {
  // Инициализация pdfrx асинхронная: её нужно дождаться ДО открытия PDF.
  await pdfrxFlutterInitialize();

  if (!Platform.isAndroid) {
    await hermesPdfFontManager.prepare();
    return;
  }

  // Android хранит системные Noto/Roboto и символьные шрифты в нескольких
  // каталогах в зависимости от версии/производителя. Передаём только реально
  // существующие пути, чтобы PDFium мог подставлять отсутствующие гарнитуры.
  const candidates = <String>[
    '/system/fonts',
    '/product/fonts',
    '/system/product/fonts',
    '/vendor/fonts',
    '/system/vendor/fonts',
  ];
  final fontPaths = candidates
      .where((path) => Directory(path).existsSync())
      .toList(growable: false);
  await hermesPdfFontManager.prepare(
    fontPaths: fontPaths.isEmpty ? null : fontPaths,
  );
}

/// Открытие бокса с защитой от повреждённых данных:
/// при ошибке чтения бокс сбрасывается, и приложение стартует.
Future<void> _openBoxSafely<T>(String name) async {
  try {
    await Hive.openBox<T>(name);
  } catch (e) {
    debugPrint('Hive: повреждён бокс "$name" ($e) — сброс');
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final suffix in ['.hive', '.lock']) {
        final f = File('${dir.path}/$name$suffix');
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    await Hive.openBox<T>(name);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializePdfEngine();

  // Hive: инициализация, адаптеры, боксы.
  await Hive.initFlutter();
  registerHiveAdapters();
  await _openBoxSafely<Account>(BoxNames.accounts);
  await _openBoxSafely<Transaction>(BoxNames.transactions);
  await _openBoxSafely<HabitTracker>(BoxNames.habits);
  await _openBoxSafely<ChatMessage>(BoxNames.chat);
  await _openBoxSafely<HermesTask>(BoxNames.tasks);
  await _openBoxSafely<JournalEntry>(BoxNames.journal);
  await _openBoxSafely<SourceDoc>(BoxNames.docs);
  await _openBoxSafely<StudySubject>(BoxNames.study);
  await _openBoxSafely<StudyParagraph>(BoxNames.studyParagraphs);

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const SystemHermesApp(),
    ),
  );
}
