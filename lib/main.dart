// Точка входа: инициализация Hive, адаптеров и SharedPreferences.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/adapters.dart';
import 'data/models.dart';
import 'services/data_sync_service.dart';
import 'services/receipt_import_service.dart';
import 'services/settings_service.dart';
import 'services/tasks_service.dart';
import 'services/journal_service.dart';
import 'services/plan/docs_service.dart';
import 'services/study/study_pdf_service.dart';
import 'services/study/study_service.dart';

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

/// Встроенные assets с реальными чеками и каталогом цен (копии из F:\Чеки и
/// F:\Цены, сохранённые в репозитории). Заполняют «Покупки» при первом запуске.
const _checkAssets = <String>[
  'assets/data/checks/check_2026-07-21_TROYKA.txt',
  'assets/data/checks/check_2026-07-12_EVROOPT.xlsx',
  'assets/data/checks/checks_2026-07-14_TROYKA_GIPPO_MYASTORG.xlsx',
];
const _pricesAsset = 'assets/data/prices/prices.json';
const _seededPrefKey = 'purchases_seeded';

/// Одноразовый сид данных покупок из assets (идемпотентен по флагу и dedupKey).
/// Чеки сохраняются в бокс, но операции в банке НЕ создаются (баланс не меняется).
Future<void> _seedBundledPurchases(SharedPreferences prefs) async {
  if (prefs.getBool(_seededPrefKey) == true) return;
  final service = ReceiptImportService(
    Hive.box<Receipt>(BoxNames.receipts),
    Hive.box<PriceEntry>(BoxNames.prices),
    (r, a) async => null,
  );
  try {
    final checks = await service.importChecksFromAssets(
      rootBundle,
      _checkAssets,
      createTransactions: false,
    );
    final prices = await service.importPricesFromJsonString(
      await rootBundle.loadString(_pricesAsset),
    );
    await prefs.setBool(_seededPrefKey, true);
    debugPrint('Сид покупок: ${checks.summary}; цены: ${prices.summary}');
  } catch (e) {
    debugPrint('Сид покупок не выполнен: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeHermesPdfEngine();

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
  await _openBoxSafely<Receipt>(BoxNames.receipts);
  await _openBoxSafely<PriceEntry>(BoxNames.prices);

  final prefs = await SharedPreferences.getInstance();

  // Одноразовый сид реальных чеков/цен из assets в боксы (без изменения баланса).
  await _seedBundledPurchases(prefs);

  // Контейнер для фоновой синхронизации данных из GitHub-каталога (без UI).
  final rootContainer = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  // Авто-синк при запуске: подтягивает data/receipts.json и data/prices.json,
  // если в настройках не выключен. Не блокирует старт интерфейса.
  unawaited(_runDataSync(rootContainer));
  // Таймер 24ч: новые чеки, опубликованные агентом, попадают в «Покупки»
  // автоматически, без перезапуска приложения.
  Timer.periodic(
    const Duration(hours: 24),
    (_) => unawaited(_runDataSync(rootContainer)),
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const SystemHermesApp(),
    ),
  );
}

/// Фоновая синхронизация чеков/цен из GitHub-каталога данных.
Future<void> _runDataSync(ProviderContainer container) async {
  try {
    final settings = container.read(settingsProvider);
    final result =
        await container.read(dataSyncServiceProvider).syncFromSettings(settings);
    debugPrint('Синк данных: ${result.summary}');
  } catch (e) {
    debugPrint('Синк данных не выполнен: $e');
  }
}
