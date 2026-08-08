// Модуль «Поиск» (в стиле Morphic/NotebookLM Research):
// вопрос → поиск в интернете (SearXNG-инстансы, фолбэк DuckDuckGo/Wikipedia)
// → LLM (Groq) составляет ответ с цитатами источников.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../agent/web_tools.dart';
import '../settings_service.dart';
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
  /// Поиск по всем провайдерам: свой SearXNG → публичные SearXNG →
  /// DDG (HTML) → DDG lite → Bing → Wikipedia. Без LLM.
  static Future<List<SearchHit>> searchWeb(
    String query, {
    String? searxngUrl,
    int limit = 6,
  }) async {
    // 0. Свой SearXNG-инстанс из настроек — самый надёжный вариант.
    final custom = (searxngUrl ?? '').trim();
    if (custom.isNotEmpty) {
      try {
        final hits = await _searxng(custom, query, limit);
        if (hits.isNotEmpty) return hits;
      } catch (_) {}
    }
    // 1. Публичные SearXNG-инстансы: пока не получим JSON с результатами.
    for (final instance in _searxngInstances) {
      try {
        final hits = await _searxng(instance, query, limit);
        if (hits.isNotEmpty) return hits;
      } catch (_) {
        // пробуем следующий инстанс
      }
    }
    // 2. DuckDuckGo (парсинг HTML).
    try {
      final hits = await WebTools.searchDdgHtml(query, limit: limit);
      if (hits.isNotEmpty) return _mapHits(hits);
    } catch (_) {}
    // 3. DuckDuckGo lite — чистая разметка, свежие новости.
    try {
      final hits = await _ddgLite(query, limit);
      if (hits.isNotEmpty) return hits;
    } catch (_) {}
    // 4. Bing — второй крупный индексатор.
    try {
      final hits = await _bing(query, limit);
      if (hits.isNotEmpty) return hits;
    } catch (_) {}
    // 5. Wikipedia API — доступна почти всегда.
    try {
      final hits = await WebTools.searchWikipedia(query, limit: limit);
      if (hits.isNotEmpty) return _mapHits(hits);
    } catch (_) {}
    throw Exception('Поисковые сервисы недоступны — проверь интернет '
        'и попробуй ещё раз.');
  }

  static List<SearchHit> _mapHits(List<WebSearchHit> hits) => hits
      .map((h) => SearchHit(title: h.title, url: h.url, snippet: h.snippet))
      .toList();

  /// Полный цикл: поиск + ответ LLM с цитатами.
  static Future<SearchAnswer> ask(
    WidgetRef ref,
    String query, {
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('Ищу в интернете…');
    final hits = await searchWeb(
      query,
      searxngUrl: ref.read(settingsProvider).searchSearxngUrl,
    );

    onStage?.call('Составляю ответ…');
    final numbered = hits.asMap().entries.map((e) {
      final i = e.key + 1;
      final h = e.value;
      final snippet = h.snippet.trim().isEmpty
          ? h.title
          : h.snippet.trim().replaceAll('\n', ' ');
      return '[$i] ${h.title.trim()}\nURL: ${h.url}\n$snippet';
    }).join('\n\n');

    final now = DateTime.now();
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    final today = '${now.day} ${months[now.month - 1]} ${now.year} года';

    final text = await llmComplete(
      ref,
      system: 'Ты — исследовательский ассистент в стиле NotebookLM. '
          'Сегодня $today. Отвечай на вопрос пользователя ПО РУССКИ, '
          'опираясь ТОЛЬКО на приведённые результаты поиска. Пиши кратко '
          'и по делу, тезисами. В нужных местах указывай источники в '
          'квадратных скобках: [1], [2]. Если вопрос касается текущих '
          'событий, а результаты устаревшие или не отвечают на вопрос — '
          'честно скажи об этом и не выдумывай, не выдавай старые данные '
          'за актуальные. Не упоминай, что у тебя есть список результатов.',
      user: 'Вопрос: $query\n\nРезультаты поиска:\n$numbered',
      maxTokens: 1200,
      timeoutSeconds: 120,
    );

    return SearchAnswer(text: text, sources: hits);
  }

  /// DuckDuckGo lite: чистая табличная разметка, свежие результаты.
  static Future<List<SearchHit>> _ddgLite(String query, int limit) async {
    final uri = Uri.parse('https://lite.duckduckgo.com/lite/')
        .replace(queryParameters: {'q': query});
    final res = await http
        .get(uri, headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final html = utf8.decode(res.bodyBytes);
    final snips = RegExp(
      r"<td class='result-snippet'>(.*?)</td>",
      dotAll: true,
    ).allMatches(html).toList();
    final hits = <SearchHit>[];
    var si = 0;
    final rows = RegExp(
      r"""<a rel="nofollow" href="//duckduckgo\.com/l/\?uddg=([^&"]+)">(.*?)</a>""",
      dotAll: true,
    ).allMatches(html);
    for (final m in rows) {
      if (hits.length >= limit) break;
      final url = Uri.decodeQueryComponent(m.group(1) ?? '');
      if (url.isEmpty) continue;
      final snippet =
          si < snips.length ? _clean(snips[si++].group(1) ?? '') : '';
      hits.add(SearchHit(
        title: _clean(m.group(2) ?? ''),
        url: url,
        snippet: snippet,
      ));
    }
    return hits;
  }

  /// Bing (HTML): блоки b_algo со ссылками и сниппетами.
  static Future<List<SearchHit>> _bing(String query, int limit) async {
    final uri = Uri.parse('https://www.bing.com/search').replace(
      queryParameters: {'q': query, 'setlang': 'ru'},
    );
    final res = await http
        .get(uri, headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final html = utf8.decode(res.bodyBytes);
    final hits = <SearchHit>[];
    final blocks =
        RegExp(r'<li class="b_algo".*?</li>', dotAll: true).allMatches(html);
    for (final b in blocks) {
      if (hits.length >= limit) break;
      final block = b.group(0) ?? '';
      final link = RegExp(r'<a class="tilk"[^>]*href="(https?://[^"]+)"')
          .firstMatch(block);
      final title = RegExp(r'<h2[^>]*>(.*?)</h2>', dotAll: true)
          .firstMatch(block);
      final snip = RegExp(r'<p class="b_lineclamp\d+">(.*?)</p>', dotAll: true)
          .firstMatch(block);
      final url = link?.group(1) ?? '';
      if (url.isEmpty) continue;
      hits.add(SearchHit(
        title: _clean(title?.group(1) ?? ''),
        url: url,
        snippet: _clean(snip?.group(1) ?? ''),
      ));
    }
    return hits;
  }

  static Future<List<SearchHit>> _searxng(
      String instance, String query, int limit) async {
    final uri = Uri.parse('$instance/search').replace(queryParameters: {
      'q': query,
      'format': 'json',
      'language': 'ru-RU',
    });
    final res = await http
        .get(uri, headers: {
          'User-Agent': _ua,
          'Accept': 'application/json',
        })
        .timeout(const Duration(seconds: 8));

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    // Некоторые инстансы отвечают HTML-заглушкой (капча/редирект) —
    // считаем это провалом и идём дальше.
    final contentType = res.headers['content-type'] ?? '';
    if (!contentType.contains('json')) {
      throw Exception('не JSON-ответ');
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
