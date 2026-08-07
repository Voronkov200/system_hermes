// Точка входа: инициализация Hive, адаптеров и SharedPreferences.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/adapters.dart';
import 'data/models.dart';
import 'services/settings_service.dart';
import 'services/tasks_service.dart';
import 'services/journal_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  // Hive: инициализация, адаптеры, боксы.
  await Hive.initFlutter();
  registerHiveAdapters();
  await Hive.openBox<Account>(BoxNames.accounts);
  await Hive.openBox<Transaction>(BoxNames.transactions);
  await Hive.openBox<MiningFarm>(BoxNames.farm);
  await Hive.openBox<HabitTracker>(BoxNames.habits);
  await Hive.openBox<ChatMessage>(BoxNames.chat);
  await Hive.openBox<LifeState>(BoxNames.life);
  await Hive.openBox<CompanionData>(BoxNames.companion);
  await Hive.openBox<ChatMessage>(BoxNames.companionChat);
  await Hive.openBox<HermesTask>(BoxNames.tasks);
  await Hive.openBox<JournalEntry>(BoxNames.journal);
  await Hive.openBox<MyPcState>(BoxNames.myPc);
  await Hive.openBox<VirtualFsFile>(BoxNames.myPcFiles);

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
