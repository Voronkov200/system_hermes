// Настройки приложения (SharedPreferences) + провайдер доступа к ним.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import 'llm_endpoint.dart';

class HermesModes {
  HermesModes._();

  static const direct = 'direct';
  static const server = 'server';
}

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
  String hermesLlmUrl; // Base URL OpenAI-совместимой модели Hermes
  String hermesLlmApiKey;
  String hermesLlmModel;
  String hermesMode; // direct | server
  String whisperApiKey; // отдельный ключ Groq только для Whisper
  String searchSearxngUrl; // свой SearXNG-инстанс для модуля «Поиск»
  bool searchOffline; // «Не искать в интернете» (3.12, 5.1.9): пропускать поиск
  bool syncEnabled; // авто-синк чеков/цен из GitHub-каталога данных
  String dataRepoBaseUrl; // база URL для data/receipts.json, data/prices.json

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
    this.hermesMode = HermesModes.direct,
    this.whisperApiKey = '',
    this.searchSearxngUrl = '',
    this.searchOffline = false,
    this.syncEnabled = true,
    this.dataRepoBaseUrl = '',
  });

  String get llmKey => normalizeApiKey(hermesLlmApiKey);
  bool get usesHermesServer =>
      hermesMode == HermesModes.server && hermesUrl.trim().isNotEmpty;
  bool get usesDirectLlm =>
      hermesMode == HermesModes.direct && llmKey.isNotEmpty;

  /// База GitHub-каталога данных. Приоритет: явная ссылка → вывод из
  /// githubOwner/githubRepo → значение по умолчанию. Всегда с завершающим «/».
  String get syncDataBaseUrl {
    final base = dataRepoBaseUrl.trim();
    if (base.isNotEmpty) return base.endsWith('/') ? base : '$base/';
    final owner = githubOwner.trim();
    final repo = githubRepo.trim();
    if (owner.isNotEmpty && repo.isNotEmpty) {
      return 'https://raw.githubusercontent.com/$owner/$repo/main/data/';
    }
    return AppConstants.defaultDataRepoBaseUrl;
  }

  /// База каталога аналитических отчётов (`data/analytics/`) — откуда приложение
  /// тянет готовые отчёты «Аналитика» (ТГК-аналитика + психпортрет).
  String get syncAnalyticsBaseUrl => '${syncDataBaseUrl}analytics/';

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
    String? hermesMode,
    String? whisperApiKey,
    String? searchSearxngUrl,
    bool? searchOffline,
    bool? syncEnabled,
    String? dataRepoBaseUrl,
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
      hermesMode: hermesMode ?? this.hermesMode,
      whisperApiKey: whisperApiKey ?? this.whisperApiKey,
      searchSearxngUrl: searchSearxngUrl ?? this.searchSearxngUrl,
      searchOffline: searchOffline ?? this.searchOffline,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      dataRepoBaseUrl: dataRepoBaseUrl ?? this.dataRepoBaseUrl,
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
    const legacyGroqUrl =
        'https://api.groq.com/openai/v1/chat/completions';
    const legacyGroqModel = 'llama-3.3-70b-versatile';
    final storedPension = prefs.getDouble(PrefKeys.pensionAmount);
    // Пенсия — подтверждённая постоянная величина, а не редактируемый бюджет.
    // Старые 450 BYN и любые тестовые значения исправляются при запуске.
    const pensionAmount = AppConstants.defaultPension;
    if (storedPension == null ||
        (storedPension - pensionAmount).abs() >= 0.001) {
      unawaited(prefs.setDouble(PrefKeys.pensionAmount, pensionAmount));
    }
    final serverApiKey = prefs.getString(PrefKeys.hermesApiKey) ?? '';
    final serverUrl = prefs.getString(PrefKeys.hermesUrl) ?? '';
    final storedLlmUrl = prefs.getString(PrefKeys.hermesLlmUrl) ??
        prefs.getString(legacyLlmUrlKey) ??
        AppConstants.hermesLlmDefaultUrl;
    final rawLlmApiKey = prefs.getString(PrefKeys.hermesLlmApiKey) ??
        prefs.getString(legacyLlmApiKey) ??
        (serverUrl.trim().isEmpty ? serverApiKey : '');
    final llmApiKey = normalizeApiKey(rawLlmApiKey);
    final storedLlmModel = prefs.getString(PrefKeys.hermesLlmModel) ??
        prefs.getString(legacyLlmModelKey) ??
        AppConstants.hermesLlmDefaultModel;
    final migrateUntouchedGroq = storedLlmUrl == legacyGroqUrl &&
        storedLlmModel == legacyGroqModel &&
        llmApiKey.trim().isEmpty;
    final llmUrl = migrateUntouchedGroq
        ? AppConstants.hermesLlmDefaultUrl
        : storedLlmUrl;
    final llmModel = migrateUntouchedGroq
        ? AppConstants.hermesLlmDefaultModel
        : storedLlmModel;
    final whisperApiKey = prefs.getString(PrefKeys.whisperApiKey) ??
        (storedLlmUrl == legacyGroqUrl ? llmApiKey : '');
    if (!prefs.containsKey(PrefKeys.hermesLlmUrl) || migrateUntouchedGroq) {
      unawaited(prefs.setString(PrefKeys.hermesLlmUrl, llmUrl));
    }
    if (!prefs.containsKey(PrefKeys.hermesLlmApiKey)) {
      unawaited(prefs.setString(PrefKeys.hermesLlmApiKey, llmApiKey));
    } else if (rawLlmApiKey != llmApiKey) {
      unawaited(prefs.setString(PrefKeys.hermesLlmApiKey, llmApiKey));
    }
    if (!prefs.containsKey(PrefKeys.hermesLlmModel) || migrateUntouchedGroq) {
      unawaited(prefs.setString(PrefKeys.hermesLlmModel, llmModel));
    }
    final storedMode = prefs.getString(PrefKeys.hermesMode);
    final hermesMode = storedMode == HermesModes.server ||
            storedMode == HermesModes.direct
        ? storedMode!
        : (serverUrl.trim().isNotEmpty &&
                llmApiKey.isEmpty
            ? HermesModes.server
            : HermesModes.direct);
    if (storedMode != hermesMode) {
      unawaited(prefs.setString(PrefKeys.hermesMode, hermesMode));
    }
    return SettingsState(
      themeMode: prefs.getString(PrefKeys.themeMode) == 'light'
          ? ThemeMode.light
          : ThemeMode.dark,
      pensionDay: prefs.getInt(PrefKeys.pensionDay) ?? AppConstants.defaultPensionDay,
      pensionAmount: pensionAmount,
      vaultPath: prefs.getString(PrefKeys.vaultPath) ?? '',
      hermesUrl: serverUrl,
      hermesApiKey: serverApiKey,
      githubOwner: prefs.getString(PrefKeys.githubOwner) ?? '',
      githubRepo: prefs.getString(PrefKeys.githubRepo) ?? '',
      lastPensionMonth: prefs.getString(PrefKeys.lastPensionMonth) ?? '',
      lastWorkoutBonusDay:
          prefs.getString(PrefKeys.workoutBonusDay) ?? '',
      hermesLlmUrl: llmUrl,
      hermesLlmApiKey: llmApiKey,
      hermesLlmModel: llmModel,
      hermesMode: hermesMode,
      whisperApiKey: whisperApiKey,
      searchSearxngUrl: prefs.getString(PrefKeys.searchSearxngUrl) ?? '',
      searchOffline: prefs.getBool(PrefKeys.searchOffline) ?? false,
      syncEnabled: prefs.getBool(PrefKeys.syncEnabled) ?? true,
      dataRepoBaseUrl: prefs.getString(PrefKeys.dataRepoBaseUrl) ?? '',
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
      hermesMode: s.hermesMode,
      whisperApiKey: s.whisperApiKey,
      searchSearxngUrl: s.searchSearxngUrl,
      searchOffline: s.searchOffline,
      syncEnabled: s.syncEnabled,
      dataRepoBaseUrl: s.dataRepoBaseUrl,
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
    await prefs.setString(PrefKeys.hermesMode, next.hermesMode);
    await prefs.setString(PrefKeys.whisperApiKey, next.whisperApiKey);
    await prefs.setString(PrefKeys.searchSearxngUrl, next.searchSearxngUrl);
    await prefs.setBool(PrefKeys.searchOffline, next.searchOffline);
    await prefs.setBool(PrefKeys.syncEnabled, next.syncEnabled);
    await prefs.setString(PrefKeys.dataRepoBaseUrl, next.dataRepoBaseUrl);
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
    await _save((n) {
      n.hermesUrl = url.trim();
      if (n.hermesUrl.isNotEmpty) {
        n.hermesMode = HermesModes.server;
      } else if (n.llmKey.isNotEmpty) {
        n.hermesMode = HermesModes.direct;
      }
    });
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
    await _save((n) {
      n.hermesLlmUrl = url.trim();
      n.hermesMode = HermesModes.direct;
    });
  }

  Future<void> setHermesLlmApiKey(String key) async {
    await _save((n) {
      n.hermesLlmApiKey = normalizeApiKey(key);
      if (n.hermesLlmApiKey.isNotEmpty) n.hermesMode = HermesModes.direct;
    });
  }

  Future<void> setHermesLlmModel(String model) async {
    await _save((n) {
      n.hermesLlmModel = model.trim();
      n.hermesMode = HermesModes.direct;
    });
  }

  Future<void> setHermesLlmProvider({
    required String baseUrl,
    required String model,
  }) async {
    await _save((n) {
      n.hermesLlmUrl = baseUrl.trim();
      n.hermesLlmModel = model.trim();
      n.hermesMode = HermesModes.direct;
    });
  }

  Future<void> setHermesMode(String mode) async {
    if (mode != HermesModes.direct && mode != HermesModes.server) return;
    await _save((n) => n.hermesMode = mode);
  }

  Future<void> setWhisperApiKey(String key) async {
    await _save((n) => n.whisperApiKey = key.trim());
  }

  Future<void> setSearchSearxngUrl(String url) async {
    await _save((n) => n.searchSearxngUrl = url.trim());
  }

  /// «Не искать в интернете» (3.12, 5.1.9): если включено — модуль
  /// «Поиск» пропускает веб-поиск и сразу идёт в LLM-диалог.
  Future<void> setSearchOffline(bool value) async {
    await _save((n) => n.searchOffline = value);
  }

  /// Вкл/выкл авто-синк чеков и цен из GitHub-каталога данных.
  Future<void> setSyncEnabled(bool value) async {
    await _save((n) => n.syncEnabled = value);
  }

  /// Явная база URL для data/receipts.json, data/prices.json (если задана —
  /// приоритетнее вывода из githubOwner/githubRepo).
  Future<void> setDataRepoBaseUrl(String url) async {
    await _save((n) => n.dataRepoBaseUrl = url.trim());
  }

}

String dateKeyLocal() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
