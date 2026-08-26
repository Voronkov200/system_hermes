// Сервис подтягивания готовых аналитических отчётов из GitHub-каталога
// data/analytics/ (tgk.json + psych.json). Приложение — только читатель (pull),
// как и для чеков/цен: ИИ-аналитика считается на ПК агентом, результат
// публикуется в GitHub, телефон тянет и показывает.
//
// VАЖНО про источник: сами данные (D:\тг, D:\акк 1) живут на ПК и недоступны
// с телефона, поэтому приложение показывает только готовый отчёт.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../features/analytics/analytics_report.dart';
import 'settings_service.dart';

/// Итог загрузки аналитики.
class AnalyticsResult {
  final AnalyticsData data;
  const AnalyticsResult(this.data);
}

/// Тянет data/analytics/tgk.json и data/analytics/psych.json.
class AnalyticsService {
  final http.Client _client;

  AnalyticsService(this._client);

  Future<AnalyticsData> load({required String baseUrl}) async {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    AnalyticsReport? tgk;
    AnalyticsReport? psych;
    String? error;

    final tgkJson = await _tryFetch('${base}tgk.json');
    if (tgkJson != null) {
      tgk = AnalyticsReport.fromJson(tgkJson);
    } else {
      error = 'tgk.json: HTTP ошибка';
    }

    final psychJson = await _tryFetch('${base}psych.json');
    if (psychJson != null) {
      psych = AnalyticsReport.fromJson(psychJson);
    } else {
      error = 'psych.json: HTTP ошибка';
    }

    return AnalyticsData(tgk: tgk, psych: psych, error: error);
  }

  Future<Map<String, dynamic>?> _tryFetch(String url) async {
    try {
      final resp = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecodeSafe(resp.body);
      return decoded;
    } catch (e) {
      return null;
    }
  }
}

Map<String, dynamic>? jsonDecodeSafe(String body) {
  try {
    final v = jsonDecode(body);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

/// Доступ к сервису.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService(http.Client());
});

/// Реактивная загрузка обоих отчётов под текущие настройки.
final analyticsReportsProvider = FutureProvider<AnalyticsData>((ref) async {
  final settings = ref.watch(settingsProvider);
  if (!settings.syncEnabled) {
    return const AnalyticsData(error: 'Синк выключен');
  }
  final service = ref.watch(analyticsServiceProvider);
  return service.load(baseUrl: settings.syncAnalyticsBaseUrl);
});
