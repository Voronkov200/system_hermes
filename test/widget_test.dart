// Базовый smoke-тест: приложение стартует без ошибок.

import 'dart:io';

import 'package:flutter/material.dart';
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

  testWidgets('App запускается с четырьмя основными областями', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const SystemHermesApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('SYSTEM'), findsWidgets);

    final navigation = find.byKey(const ValueKey('main-navigation'));
    expect(navigation, findsOneWidget);
    expect(tester.widget<NavigationBar>(navigation).destinations, hasLength(4));

    Finder navigationLabel(String label) => find.descendant(
          of: navigation,
          matching: find.text(label),
        );

    for (final label in const ['Главная', 'Работа', 'Деньги', 'Ещё']) {
      expect(navigationLabel(label), findsOneWidget);
    }

    await tester.tap(navigationLabel('Работа'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('work-screen')), findsOneWidget);
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 1);

    await tester.tap(navigationLabel('Деньги'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('money-screen')), findsOneWidget);
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 2);

    await tester.tap(navigationLabel('Ещё'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-screen')), findsOneWidget);
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 3);

    await tester.tap(navigationLabel('Главная'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-screen')), findsOneWidget);
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);

    expect(Hive.box<HabitTracker>(BoxNames.habits).get('abstinence'), isNull);
    expect(Hive.box<HabitTracker>(BoxNames.habits).get('workout_pushups'),
        isNotNull);
    expect(Hive.box<HabitTracker>(BoxNames.habits).get('workout_squat'),
        isNotNull);
  });
}
