// Настройки приложения (SharedPreferences) + провайдер доступа к ним.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Доступ к SharedPreferences (переопределяется в main()).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences не инициализированы'),
);

/// Состояние настроек (поля мутабельные для удобства _save).
class SettingsState {
  ThemeMode themeMode;
  int pensionDay;
  double pensionAmount;
  String vaultPath;
  String hermesUrl;
  String hermesApiKey;
  String githubOwner;
  String githubRepo;
  String lastPensionMonth; // '2026-08' — месяц последнего начисления
  String lastWorkoutBonusDay; // '2026-08-07' — день последнего бонуса за тренировки
  String hermesLlmUrl; // OpenAI-совместимый endpoint модели Hermes
  String hermesLlmApiKey;
  String hermesLlmModel;
  String searchSearxngUrl; // свой SearXNG-инстанс для модуля «Поиск»
  bool searchOffline; // «Не искать в интернете» (3.12, 5.1.9): пропускать поиск

  SettingsState({
    this.themeMode = ThemeMode.dark,
    this.pensionDay = AppConstants.defaultPensionDay,
    this.pensionAmount = AppConstants.defaultPension,
    this.vaultPath = '',
    this.hermesUrl = '',
    this.hermesApiKey = '',
    this.githubOwner = '',
    this.githubRepo = '',
    this.lastPensionMonth = '',
    this.lastWorkoutBonusDay = '',
    this.hermesLlmUrl = AppConstants.hermesLlmDefaultUrl,
    this.hermesLlmApiKey = '',
    this.hermesLlmModel = AppConstants.hermesLlmDefaultModel,
    this.searchSearxngUrl = '',
    this.searchOffline = false,
  });

  String get llmKey => hermesLlmApiKey.trim();

  SettingsState copyWith({
    ThemeMode? themeMode,
    int? pensionDay,
    double? pensionAmount,
    String? vaultPath,
    String? hermesUrl,
    String? hermesApiKey,
    String? githubOwner,
    String? githubRepo,
    String? lastPensionMonth,
    String? lastWorkoutBonusDay,
    String? hermesLlmUrl,
    String? hermesLlmApiKey,
    String? hermesLlmModel,
    String? searchSearxngUrl,
    bool? searchOffline,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      pensionDay: pensionDay ?? this.pensionDay,
      pensionAmount: pensionAmount ?? this.pensionAmount,
      vaultPath: vaultPath ?? this.vaultPath,
      hermesUrl: hermesUrl ?? this.hermesUrl,
      hermesApiKey: hermesApiKey ?? this.hermesApiKey,
      githubOwner: githubOwner ?? this.githubOwner,
      githubRepo: githubRepo ?? this.githubRepo,
      lastPensionMonth: lastPensionMonth ?? this.lastPensionMonth,
      lastWorkoutBonusDay: lastWorkoutBonusDay ?? this.lastWorkoutBonusDay,
      hermesLlmUrl: hermesLlmUrl ?? this.hermesLlmUrl,
      hermesLlmApiKey: hermesLlmApiKey ?? this.hermesLlmApiKey,
      hermesLlmModel: hermesLlmModel ?? this.hermesLlmModel,
      searchSearxngUrl: searchSearxngUrl ?? this.searchSearxngUrl,
      searchOffline: searchOffline ?? this.searchOffline,
    );
  }
}

/// Контроллер настроек: читает/пишет SharedPreferences.
class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    const legacyLlmUrlKey = 'companion_api_url';
    const legacyLlmApiKey = 'companion_api_key';
    const legacyLlmModelKey = 'companion_model';
    final storedPension = prefs.getDouble(PrefKeys.pensionAmount);
    // Пенсия — подтверждённая постоянная величина, а не редактируемый бюджет.
    // Старые 450 BYN и любые тестовые значения исправляются при запуске.
    const pensionAmount = AppConstants.defaultPension;
    if (storedPension == null ||
        (storedPension - pensionAmount).abs() >= 0.001) {
      unawaited(prefs.setDouble(PrefKeys.pensionAmount, pensionAmount));
    }
    final serverApiKey = prefs.getString(PrefKeys.hermesApiKey) ?? '';
    final llmUrl = prefs.getString(PrefKeys.hermesLlmUrl) ??
        prefs.getString(legacyLlmUrlKey) ??
        AppConstants.hermesLlmDefaultUrl;
    final llmApiKey = prefs.getString(PrefKeys.hermesLlmApiKey) ??
        prefs.getString(legacyLlmApiKey) ??
        serverApiKey;
    final llmModel = prefs.getString(PrefKeys.hermesLlmModel) ??
        prefs.getString(legacyLlmModelKey) ??
        AppConstants.hermesLlmDefaultModel;
    if (!prefs.containsKey(PrefKeys.hermesLlmUrl)) {
      unawaited(prefs.setString(PrefKeys.hermesLlmUrl, llmUrl));
    }
    if (!prefs.containsKey(PrefKeys.hermesLlmApiKey)) {
      unawaited(prefs.setString(PrefKeys.hermesLlmApiKey, llmApiKey));
    }
    if (!prefs.containsKey(PrefKeys.hermesLlmModel)) {
      unawaited(prefs.setString(PrefKeys.hermesLlmModel, llmModel));
    }
    return SettingsState(
      themeMode: prefs.getString(PrefKeys.themeMode) == 'light'
          ? ThemeMode.light
          : ThemeMode.dark,
      pensionDay: prefs.getInt(PrefKeys.pensionDay) ?? AppConstants.defaultPensionDay,
      pensionAmount: pensionAmount,
      vaultPath: prefs.getString(PrefKeys.vaultPath) ?? '',
      hermesUrl: prefs.getString(PrefKeys.hermesUrl) ?? '',
      hermesApiKey: serverApiKey,
      githubOwner: prefs.getString(PrefKeys.githubOwner) ?? '',
      githubRepo: prefs.getString(PrefKeys.githubRepo) ?? '',
      lastPensionMonth: prefs.getString(PrefKeys.lastPensionMonth) ?? '',
      lastWorkoutBonusDay:
          prefs.getString(PrefKeys.workoutBonusDay) ?? '',
      hermesLlmUrl: llmUrl,
      hermesLlmApiKey: llmApiKey,
      hermesLlmModel: llmModel,
      searchSearxngUrl: prefs.getString(PrefKeys.searchSearxngUrl) ?? '',
      searchOffline: prefs.getBool(PrefKeys.searchOffline) ?? false,
    );
  }

  SettingsState get s => state;

  Future<void> _save(void Function(SettingsState) apply) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final next = SettingsState(
      themeMode: s.themeMode,
      pensionDay: s.pensionDay,
      pensionAmount: s.pensionAmount,
      vaultPath: s.vaultPath,
      hermesUrl: s.hermesUrl,
      hermesApiKey: s.hermesApiKey,
      githubOwner: s.githubOwner,
      githubRepo: s.githubRepo,
      lastPensionMonth: s.lastPensionMonth,
      lastWorkoutBonusDay: s.lastWorkoutBonusDay,
      hermesLlmUrl: s.hermesLlmUrl,
      hermesLlmApiKey: s.hermesLlmApiKey,
      hermesLlmModel: s.hermesLlmModel,
      searchSearxngUrl: s.searchSearxngUrl,
      searchOffline: s.searchOffline,
    );
    apply(next);
    state = next;
    await prefs.setString(PrefKeys.themeMode, next.themeMode == ThemeMode.light ? 'light' : 'dark');
    await prefs.setInt(PrefKeys.pensionDay, next.pensionDay);
    await prefs.setDouble(PrefKeys.pensionAmount, next.pensionAmount);
    await prefs.setString(PrefKeys.vaultPath, next.vaultPath);
    await prefs.setString(PrefKeys.hermesUrl, next.hermesUrl);
    await prefs.setString(PrefKeys.hermesApiKey, next.hermesApiKey);
    await prefs.setString(PrefKeys.githubOwner, next.githubOwner);
    await prefs.setString(PrefKeys.githubRepo, next.githubRepo);
    await prefs.setString(PrefKeys.lastPensionMonth, next.lastPensionMonth);
    await prefs.setString(
        PrefKeys.workoutBonusDay, next.lastWorkoutBonusDay);
    await prefs.setString(PrefKeys.hermesLlmUrl, next.hermesLlmUrl);
    await prefs.setString(PrefKeys.hermesLlmApiKey, next.hermesLlmApiKey);
    await prefs.setString(PrefKeys.hermesLlmModel, next.hermesLlmModel);
    await prefs.setString(PrefKeys.searchSearxngUrl, next.searchSearxngUrl);
    await prefs.setBool(PrefKeys.searchOffline, next.searchOffline);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _save((n) => n.themeMode = mode);
  }

  Future<void> setPensionDay(int day) async {
    await _save((n) => n.pensionDay = day);
  }

  Future<void> setVaultPath(String path) async {
    await _save((n) => n.vaultPath = path);
  }

  Future<void> setHermesUrl(String url) async {
    await _save((n) => n.hermesUrl = url);
  }

  Future<void> setHermesApiKey(String key) async {
    await _save((n) => n.hermesApiKey = key);
  }

  Future<void> setGithub(String owner, String repo) async {
    await _save((n) {
      n.githubOwner = owner;
      n.githubRepo = repo;
    });
  }

  Future<void> setLastPensionMonth(String month) async {
    await _save((n) => n.lastPensionMonth = month);
  }

  Future<void> setWorkoutBonusDay(String day) async {
    await _save((n) => n.lastWorkoutBonusDay = day);
  }

  Future<void> setHermesLlmUrl(String url) async {
    await _save((n) => n.hermesLlmUrl = url);
  }

  Future<void> setHermesLlmApiKey(String key) async {
    await _save((n) => n.hermesLlmApiKey = key);
  }

  Future<void> setHermesLlmModel(String model) async {
    await _save((n) => n.hermesLlmModel = model);
  }

  Future<void> setSearchSearxngUrl(String url) async {
    await _save((n) => n.searchSearxngUrl = url.trim());
  }

  /// «Не искать в интернете» (3.12, 5.1.9): если включено — модуль
  /// «Поиск» пропускает веб-поиск и сразу идёт в LLM-диалог.
  Future<void> setSearchOffline(bool value) async {
    await _save((n) => n.searchOffline = value);
  }

}

String dateKeyLocal() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
