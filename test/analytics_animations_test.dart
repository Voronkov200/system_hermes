// Проверка анимированных графиков модуля «Аналитика»: рендер без исключений,
// раскрытие карточки запускает растущие графики, поля meta/structured читаются.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:system_hermes/features/analytics/analytics_report.dart';
import 'package:system_hermes/features/analytics/analytics_screen.dart';
import 'package:system_hermes/features/analytics/animated_charts.dart';
import 'package:system_hermes/services/analytics_service.dart';

void main() {
  AnalyticsData sample() {
    const tgk = AnalyticsReport(
      kind: 'tgk',
      title: 'Аналитика канала',
      subtitle: 'за ~1.5 года',
      generatedAt: 'today',
      source: 'D:\\тг',
      bodyText: 'Текст отчёта о канале.',
      bodyMarkdown: '',
      structured: {
        'theme_weights': {'Быт': 0.25, 'Учёба': 0.15, 'ИИ/IT': 0.1, 'Спорт': 0.05},
      },
      meta: {
        'total_messages': 5654,
        'monthly_activity': [
          {'month': '2025-04', 'messages': 4},
          {'month': '2025-05', 'messages': 100},
          {'month': '2025-06', 'messages': 320},
        ],
      },
    );
    const psych = AnalyticsReport(
      kind: 'psych',
      title: 'Психпортрет',
      subtitle: 'по TikTok',
      generatedAt: 'today',
      source: 'D:\\акк 1',
      bodyText: 'Психпортрет.',
      bodyMarkdown: '',
      structured: {
        'interests': ['Животные', 'Музыка'],
        'personality_traits': ['Любознательность'],
      },
      meta: {
        'n_videos': 80,
        'categories': {'Животные': 20, 'Музыка': 22, 'Быт': 21},
      },
    );
    return const AnalyticsData(tgk: tgk, psych: psych);
  }

  testWidgets('Графики рендерятся и карточка раскрывается без исключений',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsReportsProvider.overrideWith((ref) => Future.value(sample())),
        ],
        child: const MaterialApp(home: AnalyticsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Вводная карточка и заголовок модуля видны.
    expect(find.text('Аналитика о тебе'), findsOneWidget);
    expect(find.text('Аналитика канала'), findsOneWidget);

    // Раскрываем карточку ТГК, чтобы собрались растущие графики.
    await tester.tap(find.text('Аналитика канала'));
    await tester.pumpAndSettle();

    // Заголовки графиков и статы появились после раскрытия.
    expect(find.text('Вес тем'), findsOneWidget);
    expect(find.text('Активность по месяцам'), findsOneWidget);
    expect(find.text('Сообщений'), findsOneWidget);
    expect(find.text('5654'), findsOneWidget); // count-up до общего числа

    // Раскрываем психпортрет — там тоже график категорий (прокрутив к нему).
    await tester.scrollUntilVisible(find.text('Психпортрет'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Психпортрет'));
    await tester.pumpAndSettle();
    expect(find.text('Категории контента'), findsOneWidget);

    // Никаких исключений за время всех анимаций.
    expect(tester.takeException(), isNull);
  });

  testWidgets('Отдельные анимированные виджеты строятся из данных',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                FadeSlideIn(child: SizedBox(height: 20)),
                GrowingBarChart(
                  data: [BarDatum('04', 4), BarDatum('05', 100)],
                  height: 120,
                ),
                GrowingHBarChart(
                  data: [BarDatum('Быт', 25), BarDatum('Учёба', 15)],
                ),
                AnimatedCountText(target: 5654),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('5654'), findsOneWidget);
  });
}
