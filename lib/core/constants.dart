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
}

/// Имена Hive-боксов.
class BoxNames {
  BoxNames._();

  static const String accounts = 'accounts';
  static const String transactions = 'transactions';
  static const String farm = 'farm';
  static const String habits = 'habits';
  static const String chat = 'chat';
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
}
