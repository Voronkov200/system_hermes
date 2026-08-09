// Глобальные константы приложения "System: Hermes".

/// Настройки по умолчанию.
class AppConstants {
  AppConstants._();

  static const String appName = 'System: Hermes';

  /// Ежемесячная "пенсия" в BYN.
  static const double defaultPension = 450;

  /// Часть на "Топливо разработки".
  static const double defaultFuelShare = 50;

  /// День месяца получения пенсии (по умолчанию 5-е число).
  static const int defaultPensionDay = 5;

  /// Валюта "Твердых активов" по умолчанию.
  static const String defaultAssetsCurrency = 'USD';

  /// Штраф за срыв протокола (BYN).
  static const double habitFine = 25;

  /// Длительность блокировки майнинг-фермы после срыва.
  static const Duration farmLockDuration = Duration(hours: 24);

  /// URL API курсов Нацбанка РБ.
  static const String nbrbRatesUrl =
      'https://www.nbrb.by/api/exrates/rates?periodicity=0';

  /// URL GitHub API.
  static const String githubApiUrl = 'https://api.github.com';

  /// Максимум секунд начисляемых за один "тик" (защита от читов по времени).
  static const Duration maxTickGap = Duration(hours: 12);

  /// URL по умолчанию для LLM Насти и Hermes (Groq, OpenAI-совместимый).
  /// Бесплатный ключ: https://console.groq.com/keys
  static const String companionDefaultUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  /// Модель по умолчанию (бесплатная на Groq, хорошо знает русский).
  static const String companionDefaultModel = 'llama-3.3-70b-versatile';

  /// Длительность блокировки чата Насти после срыва протокола.
  static const Duration companionBlockDuration = Duration(hours: 24);

  /// Фото Насти по умолчанию (из её TikTok @nastuyshkakristmas).
  /// Используется как аватар и фон чата, пока не выбрано своё фото.
  static const String nastyaDefaultPhoto = 'assets/nastya/avatar.webp';

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

  /// Пул конкурентности (задача 2): сколько вызовов LLM (OpenCode/Groq)
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
  static const String farm = 'farm';
  static const String habits = 'habits';
  static const String chat = 'chat';
  static const String life = 'life';
  static const String companion = 'companion';
  static const String companionChat = 'companion_chat';
  static const String tasks = 'tasks';
  static const String journal = 'journal';
  static const String docs = 'docs';
}

/// Ключи настроек в SharedPreferences.
class PrefKeys {
  PrefKeys._();

  static const String themeMode = 'theme_mode'; // dark | light
  static const String pensionDay = 'pension_day';
  static const String pensionAmount = 'pension_amount';
  static const String fuelShare = 'fuel_share';
  static const String assetsCurrency = 'assets_currency';
  static const String vaultPath = 'vault_path';
  static const String hermesUrl = 'hermes_url';
  static const String hermesApiKey = 'hermes_api_key';
  static const String githubOwner = 'github_owner';
  static const String githubRepo = 'github_repo';
  static const String lastPensionMonth = 'last_pension_month';
  static const String protocolStart = 'protocol_start';
  static const String workoutBonusDay = 'workout_bonus_day';
  static const String companionApiUrl = 'companion_api_url';
  static const String companionApiKey = 'companion_api_key';
  static const String companionModel = 'companion_model';
  static const String searchSearxngUrl = 'search_searxng_url';
  static const String searchOffline = 'search_offline';
}
