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
  String protocolStart; // дата начала протокола (для стрика)
  String lastWorkoutBonusDay; // '2026-08-07' — день последнего бонуса за тренировки
  String companionApiUrl; // LLM для Анастасии (Groq-совместимый)
  String companionApiKey;
  String companionModel;
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
    this.protocolStart = '',
    this.lastWorkoutBonusDay = '',
    this.companionApiUrl = AppConstants.companionDefaultUrl,
    this.companionApiKey = '',
    this.companionModel = AppConstants.companionDefaultModel,
    this.searchSearxngUrl = '',
    this.searchOffline = false,
  });

  /// Ключ для LLM Hermes: свой ключ, либо ключ Анастасии, либо пусто.
  String get llmKey => hermesApiKey.trim().isNotEmpty
      ? hermesApiKey.trim()
      : companionApiKey.trim();

  /// Ключ для LLM Анастасии: свой ключ, либо ключ Hermes, либо пусто.
  String get companionKey => companionApiKey.trim().isNotEmpty
      ? companionApiKey.trim()
      : hermesApiKey.trim();

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
    String? protocolStart,
    String? lastWorkoutBonusDay,
    String? companionApiUrl,
    String? companionApiKey,
    String? companionModel,
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
      protocolStart: protocolStart ?? this.protocolStart,
      lastWorkoutBonusDay: lastWorkoutBonusDay ?? this.lastWorkoutBonusDay,
      companionApiUrl: companionApiUrl ?? this.companionApiUrl,
      companionApiKey: companionApiKey ?? this.companionApiKey,
      companionModel: companionModel ?? this.companionModel,
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
    final storedPension = prefs.getDouble(PrefKeys.pensionAmount);
    // Пенсия — подтверждённая постоянная величина, а не редактируемый бюджет.
    // Старые 450 BYN и любые тестовые значения исправляются при запуске.
    const pensionAmount = AppConstants.defaultPension;
    if (storedPension == null ||
        (storedPension - pensionAmount).abs() >= 0.001) {
      unawaited(prefs.setDouble(PrefKeys.pensionAmount, pensionAmount));
    }
    return SettingsState(
      themeMode: prefs.getString(PrefKeys.themeMode) == 'light'
          ? ThemeMode.light
          : ThemeMode.dark,
      pensionDay: prefs.getInt(PrefKeys.pensionDay) ?? AppConstants.defaultPensionDay,
      pensionAmount: pensionAmount,
      vaultPath: prefs.getString(PrefKeys.vaultPath) ?? '',
      hermesUrl: prefs.getString(PrefKeys.hermesUrl) ?? '',
      hermesApiKey: prefs.getString(PrefKeys.hermesApiKey) ?? '',
      githubOwner: prefs.getString(PrefKeys.githubOwner) ?? '',
      githubRepo: prefs.getString(PrefKeys.githubRepo) ?? '',
      lastPensionMonth: prefs.getString(PrefKeys.lastPensionMonth) ?? '',
      protocolStart: prefs.getString(PrefKeys.protocolStart) ?? '',
      lastWorkoutBonusDay:
          prefs.getString(PrefKeys.workoutBonusDay) ?? '',
      companionApiUrl: prefs.getString(PrefKeys.companionApiUrl) ??
          AppConstants.companionDefaultUrl,
      companionApiKey: prefs.getString(PrefKeys.companionApiKey) ?? '',
      companionModel: prefs.getString(PrefKeys.companionModel) ??
          AppConstants.companionDefaultModel,
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
      protocolStart: s.protocolStart,
      lastWorkoutBonusDay: s.lastWorkoutBonusDay,
      companionApiUrl: s.companionApiUrl,
      companionApiKey: s.companionApiKey,
      companionModel: s.companionModel,
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
    await prefs.setString(PrefKeys.protocolStart, next.protocolStart);
    await prefs.setString(
        PrefKeys.workoutBonusDay, next.lastWorkoutBonusDay);
    await prefs.setString(PrefKeys.companionApiUrl, next.companionApiUrl);
    await prefs.setString(PrefKeys.companionApiKey, next.companionApiKey);
    await prefs.setString(PrefKeys.companionModel, next.companionModel);
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

  Future<void> setCompanionApiUrl(String url) async {
    await _save((n) => n.companionApiUrl = url);
  }

  Future<void> setCompanionApiKey(String key) async {
    await _save((n) => n.companionApiKey = key);
  }

  Future<void> setCompanionModel(String model) async {
    await _save((n) => n.companionModel = model);
  }

  Future<void> setSearchSearxngUrl(String url) async {
    await _save((n) => n.searchSearxngUrl = url.trim());
  }

  /// «Не искать в интернете» (3.12, 5.1.9): если включено — модуль
  /// «Поиск» пропускает веб-поиск и сразу идёт в LLM-диалог.
  Future<void> setSearchOffline(bool value) async {
    await _save((n) => n.searchOffline = value);
  }

  Future<void> ensureProtocolStart() async {
    if (s.protocolStart.isNotEmpty) return;
    await _save((n) => n.protocolStart = dateKeyLocal());
  }
}

String dateKeyLocal() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
