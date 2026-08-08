// Модуль «Поиск» (в стиле Morphic/NotebookLM Research):
// вопрос → поиск в интернете (SearXNG-инстансы, фолбэк DuckDuckGo/Wikipedia)
// → LLM (Groq) составляет ответ с цитатами источников.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../agent/web_tools.dart';
import 'llm.dart';

/// Публичные SearXNG-инстансы: пробуем по очереди, пока не получим ответ.
const _searxngInstances = [
  'https://searx.be',
  'https://searx.tiekoetter.com',
  'https://paulgo.io',
  'https://search.bus-hit.me',
  'https://priv.au',
  'https://searxng.site',
];

const _ua =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/125.0 Mobile Safari/537.36';

/// Результат поиска.
class SearchHit {
  final String title;
  final String url;
  final String snippet;

  const SearchHit({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

/// Итог: ответ модели + найденные источники.
class SearchAnswer {
  final String text;
  final List<SearchHit> sources;

  const SearchAnswer({required this.text, required this.sources});
}

class SearchService {
  /// Поиск по всем провайдерам (SearXNG → DDG/Wikipedia), без LLM.
  static Future<List<SearchHit>> searchWeb(String query, {int limit = 6}) async {
    for (final instance in _searxngInstances) {
      try {
        final hits = await _searxng(instance, query, limit);
        if (hits.isNotEmpty) return hits;
      } catch (_) {
        // пробуем следующий инстанс
      }
    }
    // Фолбэк: DuckDuckGo + Wikipedia (как в агенте Hermes).
    final hits = await WebTools.searchStructured(query, limit: limit);
    if (hits.isEmpty) {
      throw Exception('Поиск ничего не нашёл по запросу «$query».');
    }
    return hits
        .map((h) => SearchHit(title: h.title, url: h.url, snippet: h.snippet))
        .toList();
  }

  /// Полный цикл: поиск + ответ LLM с цитатами.
  static Future<SearchAnswer> ask(
    WidgetRef ref,
    String query, {
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('Ищу в интернете…');
    final hits = await searchWeb(query);

    onStage?.call('Составляю ответ…');
    final numbered = hits.asMap().entries.map((e) {
      final i = e.key + 1;
      final h = e.value;
      final snippet = h.snippet.trim().isEmpty
          ? h.title
          : h.snippet.trim().replaceAll('\n', ' ');
      return '[$i] ${h.title.trim()}\nURL: ${h.url}\n$snippet';
    }).join('\n\n');

    final text = await llmComplete(
      ref,
      system: 'Ты — исследовательский ассистент в стиле NotebookLM. '
          'Отвечай на вопрос пользователя ПО РУССКИ, опираясь ТОЛЬКО на '
          'приведённые результаты поиска. Пиши кратко и по делу, тезисами. '
          'В нужных местах указывай источники в квадратных скобках: [1], [2]. '
          'Если в результатах нет ответа на вопрос — честно скажи об этом и '
          'не выдумывай. Не упоминай, что у тебя есть список результатов.',
      user: 'Вопрос: $query\n\nРезультаты поиска:\n$numbered',
      maxTokens: 1200,
      timeoutSeconds: 120,
    );

    return SearchAnswer(text: text, sources: hits);
  }

  static Future<List<SearchHit>> _searxng(
      String instance, String query, int limit) async {
    final uri = Uri.parse('$instance/search').replace(queryParameters: {
      'q': query,
      'format': 'json',
      'language': 'ru-RU',
    });
    final res = await http
        .get(uri, headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final raw = (data['results'] as List? ?? const []).cast<Map>();
    return raw.take(limit).map((r) {
      final rw = r.cast<String, dynamic>();
      final title = _clean(rw['title'] as String? ?? '');
      final url = (rw['url'] as String? ?? '').trim();
      final snippet = _clean(rw['content'] as String? ?? '');
      return SearchHit(title: title, url: url, snippet: snippet);
    }).toList();
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
