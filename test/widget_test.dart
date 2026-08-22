// Базовый smoke-тест: приложение стартует без ошибок.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:system_hermes/app.dart';
import 'package:system_hermes/core/constants.dart';
import 'package:system_hermes/data/adapters.dart';
import 'package:system_hermes/data/models.dart';
import 'package:system_hermes/services/journal_service.dart';
import 'package:system_hermes/services/settings_service.dart';
import 'package:system_hermes/services/tasks_service.dart';
import 'package:system_hermes/services/plan/docs_service.dart';

void main() {
  setUpAll(() async {
    // Hive в памяти для теста
    Hive.init(Directory.systemTemp.createTempSync('hermes_test').path);
    registerHiveAdapters();
    await Hive.openBox<Account>(BoxNames.accounts);
    await Hive.openBox<Transaction>(BoxNames.transactions);
    final habits = await Hive.openBox<HabitTracker>(BoxNames.habits);
    await habits.put(
      'abstinence',
      HabitTracker(
        id: 'abstinence',
        name: 'Устаревшая привычка',
        type: 'bad',
      ),
    );
    await Hive.openBox<ChatMessage>(BoxNames.chat);
    await Hive.openBox<LifeState>(BoxNames.life);
    await Hive.openBox<HermesTask>(BoxNames.tasks);
    await Hive.openBox<JournalEntry>(BoxNames.journal);
    await Hive.openBox<SourceDoc>(BoxNames.docs);

    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App запускается', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const SystemHermesApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('SYSTEM'), findsWidgets);
    expect(Hive.box<HabitTracker>(BoxNames.habits).get('abstinence'), isNull);
    expect(Hive.box<HabitTracker>(BoxNames.habits).get('workout_pushups'),
        isNotNull);
    expect(Hive.box<HabitTracker>(BoxNames.habits).get('workout_squat'),
        isNotNull);
  });
}
