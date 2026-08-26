// Модели данных «Аналитика»: готовые ИИ-отчёты, которые приложение тянет из
// GitHub (data/analytics/). Не хранятся в Hive — подтягиваются по требованию.

/// Один готовый аналитический отчёт (ТГК-аналитика или психпортрет TikTok).
class AnalyticsReport {
  final String kind; // 'tgk' | 'psych'
  final String title;
  final String subtitle;
  final String generatedAt;
  final String source;
  final String bodyText; // читаемый plain-text (для отображения)
  final String bodyMarkdown; // исходный markdown (для богатого рендера)
  final Map<String, dynamic> structured; // структурированные данные (темы, черты и т.п.)
  final Map<String, dynamic> meta; // служебные данные (monthly_activity, период и т.д.)

  const AnalyticsReport({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.generatedAt,
    required this.source,
    required this.bodyText,
    required this.bodyMarkdown,
    required this.structured,
    this.meta = const {},
  });

  factory AnalyticsReport.fromJson(Map<String, dynamic> json) {
    return AnalyticsReport(
      kind: json['kind'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      generatedAt: json['generatedAt'] as String? ?? '',
      source: json['source'] as String? ?? '',
      bodyText: json['body_text'] as String? ?? '',
      bodyMarkdown: json['body_markdown'] as String? ?? '',
      structured: (json['structured'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      meta: (json['meta'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// Помесячная активность из meta (массив {month, messages, chars, active_days}).
  List<Map<String, dynamic>> monthlyActivity() {
    final raw = meta['monthly_activity'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  /// Первая строка структурированного поля для быстрой сводки.
  List<String> structuredList(String key) {
    final raw = structured[key];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const [];
  }

  Map<String, dynamic> structuredMap(String key) {
    final raw = structured[key];
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }
}

/// Связка обоих отчётов + ошибка загрузки.
class AnalyticsData {
  final AnalyticsReport? tgk;
  final AnalyticsReport? psych;
  final String? error;

  const AnalyticsData({this.tgk, this.psych, this.error});

  bool get hasAny => tgk != null || psych != null;
}
