// Точка входа: инициализация Hive, адаптеров и SharedPreferences.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/adapters.dart';
import 'data/models.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive: инициализация, адаптеры, боксы.
  await Hive.initFlutter();
  registerHiveAdapters();
  await Hive.openBox<Account>(BoxNames.accounts);
  await Hive.openBox<Transaction>(BoxNames.transactions);
  await Hive.openBox<MiningFarm>(BoxNames.farm);
  await Hive.openBox<HabitTracker>(BoxNames.habits);
  await Hive.openBox<ChatMessage>(BoxNames.chat);
  await Hive.openBox<LifeState>(BoxNames.life);

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
