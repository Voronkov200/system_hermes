// Тесты модуля «Аналитика»: парсинг отчётов из GitHub-формата.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:system_hermes/features/analytics/analytics_report.dart';
import 'package:system_hermes/services/analytics_service.dart';

const _tgkJson = {
  'kind': 'tgk',
  'title': 'Аналитика ТГК «Повседневная жизнь с Chat GPT»',
  'subtitle': 'Период: 2025-04-24 → 2026-08-23 · 5654 сообщений',
  'generatedAt': '2026-08-26 11:14',
  'source': r'D:\тг',
  'body_text': '## Аналитический отчёт\nКанал — личный видео-дневник.',
  'body_markdown': '## Аналитический отчёт\nКанал — личный видео-дневник.',
  'structured': {
    'theme_weights': {'Быт/повседневность': 0.20, 'Учёба/школа': 0.12},
    'conclusions': ['Канал — дневник', 'Интересы растут'],
    'psych_profile': {
      'traits': ['разговорчивый', 'рефлексирующий'],
      'emotions': 'Переменчивый фон',
    },
  },
  'meta': {'total_messages': 5654},
};

const _psychJson = {
  'kind': 'psych',
  'title': 'Психологический портрет (TikTok / избранное)',
  'subtitle': '71 расшифровок',
  'generatedAt': '2026-08-26 11:14',
  'source': 'D:\\акк 1 → Favorites/videos',
  'body_text': '## Портрет\nИнтересы к животным и музыке.',
  'body_markdown': '## Портрет\nИнтересы к животным.',
  'structured': {
    'interests': ['музыка', 'животные'],
    'personality_traits': ['аналитичный', 'практичный'],
  },
};

void main() {
  group('AnalyticsReport.fromJson', () {
    test('разбирает tgk-отчёт вместе с структурированными данными', () {
      final r = AnalyticsReport.fromJson(_tgkJson);
      expect(r.kind, 'tgk');
      expect(r.title, contains('Повседневная жизнь'));
      expect(r.subtitle, contains('5654'));
      expect(r.bodyText, contains('видео-дневник'));
      expect(r.source, contains(r'D:\тг'));

      final weights = r.structuredMap('theme_weights');
      expect(weights['Быт/повседневность'], 0.20);
      expect(weights['Учёба/школа'], 0.12);

      final conclusions = r.structuredList('conclusions');
      expect(conclusions, hasLength(2));
      expect(conclusions.first, 'Канал — дневник');
    });

    test('разбирает psych-отчёт и достаёт interests/черты', () {
      final r = AnalyticsReport.fromJson(_psychJson);
      expect(r.kind, 'psych');
      expect(r.structuredList('interests'), contains('музыка'));
      expect(r.structuredList('personality_traits'), contains('аналитичный'));
    });
  });

  group('AnalyticsService.load', () {
    test('загружает оба отчёта через MockClient и разбирает их', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/tgk.json')) {
          return http.Response(jsonEncode(_tgkJson), 200,
              headers: {'content-type': 'application/json'});
        }
        if (request.url.path.endsWith('/psych.json')) {
          return http.Response(jsonEncode(_psychJson), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('not found', 404);
      });

      final service = AnalyticsService(client);
      final data = await service.load(baseUrl: 'https://example/data/analytics/');

      expect(data.error, isNull);
      expect(data.tgk, isNotNull);
      expect(data.psych, isNotNull);
      expect(data.tgk!.title, contains('ТГК'));
      expect(data.psych!.title, contains('портрет'));
      expect(data.hasAny, isTrue);
    });

    test('при HTTP ошибке возвращает null-отчёт и error', () async {
      final client = MockClient((_) async => http.Response('err', 500));
      final service = AnalyticsService(client);
      final data = await service.load(baseUrl: 'https://example/data/analytics/');
      expect(data.tgk, isNull);
      expect(data.psych, isNull);
      expect(data.error, isNotNull);
      expect(data.hasAny, isFalse);
    });
  });
}
