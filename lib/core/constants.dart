// Глобальные константы приложения "System: Hermes".

/// Настройки по умолчанию.
class AppConstants {
  AppConstants._();

  static const String appName = 'System: Hermes';

  /// Официальная ежемесячная пенсия в BYN.
  static const double defaultPension = 390;

  /// День месяца получения пенсии (по умолчанию 5-е число).
  static const int defaultPensionDay = 5;

  /// URL API курсов Нацбанка РБ.
  static const String nbrbRatesUrl =
      'https://www.nbrb.by/api/exrates/rates?periodicity=0';

  /// URL GitHub API.
  static const String githubApiUrl = 'https://api.github.com';

  /// Максимум секунд начисляемых за один "тик" (защита от читов по времени).
  static const Duration maxTickGap = Duration(hours: 12);

  /// Base URL B.ai — OpenAI-совместимого провайдера Hermes.
  static const String hermesLlmDefaultUrl = 'https://api.b.ai/v1';

  /// Основная текстовая модель Hermes на B.ai.
  static const String hermesLlmDefaultModel = 'deepseek-v4-flash';

  // ===================================================================
  // Поиск и исследования (спецификация, разделы 3.3, 6)
  // ===================================================================

  /// TTL кэша «Исследования» в часах (задача 1): единая константа вместо
  /// разрозненных «сутки»/«час». Используется в логике кэша и в описании
  /// тестового сценария 6 (раздел 4.7).
  static const int researchCacheTtlHours = 24;

  /// TTL кэша «Поиска» (3.3): короткий кэш идентичных запросов.
  static const Duration searchCacheTtl = Duration(minutes: 5);

  /// TTL кэша Стадии −1 «Поиска» (3.3): погода/курсы валют не кэшируются
  /// дольше 15 минут.
  static const Duration stageMinusOneCacheTtl = Duration(minutes: 15);

  /// Пул конкурентности (задача 2): сколько поисковых вызовов
  /// (Tavily/SearXNG/HTML-провайдеры) выполняется параллельно.
  static const int maxConcurrentSearches = 4;

  /// Пул конкурентности (задача 2): сколько вызовов LLM
  /// выполняется параллельно.
  static const int maxConcurrentLlm = 2;

  /// Retry (задача 2): задержки 1с → 2с → 4с, максимум 3 попытки.
  static const int retryAttempts = 3;

  /// Лимит источников после фильтрации (2.5).
  static const int maxSources = 5;
}

/// Имена Hive-боксов.
class BoxNames {
  BoxNames._();

  static const String accounts = 'accounts';
  static const String transactions = 'transactions';
  static const String habits = 'habits';
  static const String chat = 'chat';
  static const String tasks = 'tasks';
  static const String journal = 'journal';
  static const String docs = 'docs';
  static const String study = 'study';
  static const String studyParagraphs = 'study_paragraphs';
}

/// Ключи настроек в SharedPreferences.
class PrefKeys {
  PrefKeys._();

  static const String themeMode = 'theme_mode'; // dark | light
  static const String pensionDay = 'pension_day';
  static const String pensionAmount = 'pension_amount';
  static const String vaultPath = 'vault_path';
  static const String hermesUrl = 'hermes_url';
  static const String hermesApiKey = 'hermes_api_key';
  static const String githubOwner = 'github_owner';
  static const String githubRepo = 'github_repo';
  static const String lastPensionMonth = 'last_pension_month';
  static const String workoutBonusDay = 'workout_bonus_day';
  static const String hermesLlmUrl = 'hermes_llm_url';
  static const String hermesLlmApiKey = 'hermes_llm_api_key';
  static const String hermesLlmModel = 'hermes_llm_model';
  static const String hermesMode = 'hermes_mode';
  static const String whisperApiKey = 'whisper_api_key';
  static const String searchSearxngUrl = 'search_searxng_url';
  static const String searchOffline = 'search_offline';
}
