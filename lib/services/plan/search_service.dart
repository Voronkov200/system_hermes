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

/// Десктопный UA — нужен для провайдеров, отдающих мобильным капчу
/// (Brave, Yahoo).
const _uaDesktop =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0 Safari/537.36';

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
  /// Последний провайдер, который реально отдал результаты. Многие
  /// сервисы (DDG, SearXNG) периодически блокируют ботов капчей, поэтому
  /// в начале следующего поиска пробуем то, что работало недавно.
  static String? _lastGoodProvider;

  /// Технический лог последнего поиска: что искали, каким провайдером,
  /// сколько нашли. Показывается под ответом (диагностика).
  static final List<String> log = [];

  static void _log(String line) {
    final now = DateTime.now();
    final t = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    log.add('$t $line');
    if (log.length > 40) log.removeAt(0);
  }

  /// Порядок HTML-провайдеров для перебора.
  static const _providerOrder = [
    'ddg', // DuckDuckGo HTML
    'ddgLite', // DuckDuckGo lite
    'bing', // Bing
    'brave', // Brave Search
    'yahoo', // Yahoo (со сниженным приоритетом из-за сущностей в заголовках)
    'wiki', // Wikipedia API — доступна почти всегда
  ];

  /// Признаки того, что текст похож на плохо распознанную речь
  /// (обрывки, случайные цифры, шум). Возвращает причину или null.
  static String? looksBrokenSpeech(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'пустой текст';
    if (t.length < 5) return 'фраза слишком короткая';
    final digits = RegExp(r'\d').allMatches(t).length;
    if (digits >= 4 && digits * 100 ~/ t.length > 15) {
      return 'много случайных цифр';
    }
    final words =
        t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2) return 'меньше двух слов';
    final cyr = RegExp(r'[а-яА-ЯёЁ]').allMatches(t).length;
    final lat = RegExp(r'[a-zA-Z]').allMatches(t).length;
    if (lat + digits > cyr * 3 && lat > digits) {
      return 'набор латинских слов и цифр без смысла';
    }
    if (cyr == 0 && lat == 0) return 'нет букв';
    return null;
  }

  /// Поиск по всем провайдерам: свой SearXNG → публичные SearXNG →
  /// DDG (HTML) → DDG lite → Bing → Brave → Yahoo → Wikipedia. Без LLM.
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
        if (hits.isNotEmpty) {
          _log('Провайдер: свой SearXNG (${hits.length})');
          return hits;
        }
      } catch (_) {}
    }
    // 0.5. Последний рабочий HTML-провайдер — ускоряет повторные поиски
    // и обходит временные блокировки.
    final saved = _lastGoodProvider;
    if (saved != null) {
      try {
        final hits = await _via(saved, query, limit);
        if (hits.isNotEmpty) {
          _log('Провайдер: $saved (кэш, ${hits.length})');
          return hits;
        }
      } catch (_) {}
    }
    // 1. Публичные SearXNG-инстансы: пока не получим JSON с результатами.
    for (final instance in _searxngInstances) {
      try {
        final hits = await _searxng(instance, query, limit);
        if (hits.isNotEmpty) {
          _log('Провайдер: $instance (${hits.length})');
          return hits;
        }
      } catch (_) {
        // пробуем следующий инстанс
      }
    }
    // 2-7. HTML-провайдеры по порядку.
    for (final name in _providerOrder) {
      try {
        final hits = await _via(name, query, limit);
        if (hits.isNotEmpty) {
          _lastGoodProvider = name;
          _log('Провайдер: $name (${hits.length})');
          return hits;
        }
      } catch (_) {
        // пробуем следующий
      }
    }
    throw Exception('Поисковые сервисы недоступны — проверь интернет '
        'и попробуй ещё раз.');
  }

  /// Поиск с переписыванием запроса: LLM превращает человеческий вопрос
  /// в 2-3 коротких поисковых запроса, каждый ищется отдельно, дубли
  /// убираются. Если переписывание упало — ищем как есть.
  static Future<List<SearchHit>> searchWebRewritten(
    WidgetRef ref,
    String query, {
    void Function(String stage)? onStage,
    int limit = 6,
  }) async {
    final searxngUrl = ref.read(settingsProvider).searchSearxngUrl;
    final queries = await _rewriteQueries(ref, query);
    _log('Переписанные запросы: ${queries.join(' | ')}');
    final all = <SearchHit>[];
    final seen = <String>{};
    for (final q in queries) {
      onStage?.call('Ищу: "$q"');
      try {
        final hits = await searchWeb(q, searxngUrl: searxngUrl, limit: 5);
        for (final h in hits) {
          if (seen.add(h.url)) all.add(h);
        }
      } catch (_) {}
      if (all.length >= limit * 2) break;
    }
    if (all.isEmpty) {
      // Фолбэк: ищем исходную фразу целиком.
      onStage?.call('Ищу: "$query"');
      _log('Переписывание не дало результатов — ищу исходную фразу.');
      try {
        final hits = await searchWeb(query, searxngUrl: searxngUrl,
            limit: limit);
        for (final h in hits) {
          if (seen.add(h.url)) all.add(h);
        }
      } catch (e) {
        _log('Провал: $e');
        rethrow;
      }
    }
    final out = all.take(limit).toList();
    _log('Итого источников: ${out.length}');
    return out;
  }

  /// LLM переписывает вопрос в короткие поисковые запросы.
  static Future<List<String>> _rewriteQueries(
      WidgetRef ref, String query) async {
    final today = _todayStr();
    try {
      final raw = await llmComplete(
        ref,
        system: 'Ты — эксперт по поисковым запросам. Сегодня $today. '
            'Преврати вопрос пользователя в 2-3 коротких поисковых запроса, '
            'по одному на строку, без нумерации и кавычек. Каждый запрос — '
            'отдельный ракурс темы, 3-8 слов, фактологичный. Если вопрос '
            'уже короткий и чёткий — верни его одним запросом.',
        user: 'Вопрос: $query',
        maxTokens: 300,
        timeoutSeconds: 60,
      );
      final qs = raw
          .split('\n')
          .map((l) => l.trim().replaceAll(RegExp(r'^[-*\d.)\s]+'), ''))
          .where((l) => l.length >= 4 && l.length <= 120)
          .take(3)
          .toList();
      return qs.isEmpty ? [query] : qs;
    } catch (_) {
      return [query];
    }
  }

  /// Запуск HTML-провайдера по имени.
  static Future<List<SearchHit>> _via(
      String name, String query, int limit) async {
    return switch (name) {
      'ddg' => _mapHits(await WebTools.searchDdgHtml(query, limit: limit)),
      'ddgLite' => await _ddgLite(query, limit),
      'bing' => await _bing(query, limit),
      'brave' => await _brave(query, limit),
      'yahoo' => await _yahoo(query, limit),
      'wiki' => _mapHits(await WebTools.searchWikipedia(query, limit: limit)),
      _ => throw Exception('Неизвестный провайдер: $name'),
    };
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
    _gateInput(query);
    onStage?.call('Планирую поиск…');
    final hits = await searchWebRewritten(
      ref,
      query,
      onStage: onStage,
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

    final today = _todayStr();

    final text = await llmComplete(
      ref,
      system: 'Ты — исследовательский ассистент в стиле NotebookLM. '
          'Сегодня $today. Отвечай на вопрос пользователя ПО РУССКИ, '
          'опираясь ТОЛЬКО на приведённые результаты поиска. Оформляй ответ '
          'структурированно: 1-й абзац — суть в 2-3 предложениях, затем '
          'тезисы с тире, при списках — маркеры "-". Пиши кратко и по делу. '
          'В нужных местах указывай источники в квадратных скобках: [1], [2]. '
          'Если вопрос касается текущих событий, а результаты устаревшие '
          'или не отвечают на вопрос — честно скажи об этом и не выдумывай, '
          'не выдавай старые данные за актуальные. Не упоминай, что у тебя '
          'есть список результатов.',
      user: 'Вопрос: $query\n\nРезультаты поиска:\n$numbered',
      maxTokens: 1200,
      timeoutSeconds: 120,
    );

    return SearchAnswer(text: text, sources: hits);
  }

  /// Проверка входного текста: если похоже на сбой распознавания речи —
  /// не ищем, а просим уточнить.
  static void _gateInput(String query) {
    final reason = looksBrokenSpeech(query);
    if (reason != null) {
      throw Exception('Похоже, я неправильно распознал твою речь: '
          '"${query.trim()}" ($reason). Повтори фразу чётче или напиши '
          'текстом — и я поищу.');
    }
  }

  /// Глубокое исследование (стиль Deep Research): тема → подвопросы →
  /// поиск по каждому → подробный отчёт с цитатами [n] на все источники.
  static Future<SearchAnswer> deepResearch(
    WidgetRef ref,
    String query, {
    void Function(String stage)? onStage,
  }) async {
    _gateInput(query);
    final today = _todayStr();

    // 1. План: уточняющие подвопросы.
    onStage?.call('Планирую исследование…');
    final plan = await llmComplete(
      ref,
      system: 'Ты — планировщик исследования. Сегодня $today. '
          'Составь 4-5 уточняющих подвопросов по теме пользователя, '
          'по одному на строку, без нумерации и кавычек. Подвопросы должны '
          'покрывать: текущее состояние, причины и контекст, конкретные '
          'примеры и цифры, перспективы и критику.',
      user: 'Тема исследования: $query',
      maxTokens: 400,
      timeoutSeconds: 60,
    );
    final subqs = plan
        .split('\n')
        .map((l) => l.trim().replaceAll(RegExp(r'^[-*\d.)\s]+'), ''))
        .where((l) => l.length > 8)
        .take(5)
        .toList();
    if (subqs.isEmpty) {
      throw Exception('Не удалось составить план исследования.');
    }

    // 2. Поиск по каждому подвопросу, сквозная нумерация источников.
    final allHits = <SearchHit>[];
    final seen = <String>{};
    final blocks = StringBuffer();
    var globalIdx = 0;
    for (var i = 0; i < subqs.length; i++) {
      onStage?.call('Изучаю подвопрос ${i + 1} из ${subqs.length}…');
      List<SearchHit> hits = const [];
      try {
        hits = await searchWebRewritten(
          ref,
          subqs[i],
          onStage: onStage,
          limit: 5,
        );
      } catch (_) {}
      if (hits.isEmpty) {
        blocks.writeln('Подвопрос: ${subqs[i]}\n(результатов не найдено)');
        continue;
      }
      blocks.writeln('Подвопрос: ${subqs[i]}');
      for (final h in hits) {
        if (!seen.add(h.url)) continue;
        globalIdx++;
        final snippet = h.snippet.trim().isEmpty
            ? h.title
            : h.snippet.trim().replaceAll('\n', ' ');
        blocks.writeln(
            '[$globalIdx] ${h.title.trim()}\nURL: ${h.url}\n$snippet');
        allHits.add(h);
      }
      blocks.writeln();
    }
    if (allHits.isEmpty) {
      throw Exception('Поисковые сервисы недоступны — нечего анализировать.');
    }

    // 3. Сводный отчёт.
    onStage?.call('Составляю отчёт…');
    final text = await llmComplete(
      ref,
      system: 'Ты — аналитик-исследователь (стиль NotebookLM Deep Research). '
          'Сегодня $today. Напиши ПОДРОБНЫЙ структурированный отчёт по теме '
          'пользователя на русском, используя только результаты поиска, '
          'сгруппированные по подвопросам. Структура отчёта: '
          '1) «Суть» — 2-3 предложения; 2) раздел по каждому подвопросу с '
          'фактами, цифрами и примерами; 3) «Выводы» — итог и перспективы. '
          'Каждый факт подкрепляй источником в квадратных скобках: [1], [2]. '
          'Не выдумывай данные; если информации не хватает — честно скажи. '
          'Не упоминай, что у тебя есть список результатов.',
      user: 'Тема: $query\n\nРезультаты по подвопросам:\n$blocks',
      maxTokens: 4000,
      timeoutSeconds: 300,
    );

    return SearchAnswer(text: text, sources: allHits);
  }

  static String _todayStr() {
    final now = DateTime.now();
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year} года';
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
      r"""<a rel="nofollow" href="//duckduckgo\.com/l/\?uddg=([^"]+)"[^>]*>(.*?)</a>""",
      dotAll: true,
    ).allMatches(html);
    for (final m in rows) {
      if (hits.length >= limit) break;
      // Значение uddg заканчивается на первом & (в HTML — &amp; перед rut).
      final encoded = (m.group(1) ?? '').split('&').first;
      if (encoded.isEmpty) continue;
      final url = Uri.decodeQueryComponent(encoded);
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

  /// Brave Search (HTML): блоки snippet, заголовок в title-атрибуте.
  /// Отдаёт результаты даже с десктопным UA, когда DDG уже показывает капчу.
  static Future<List<SearchHit>> _brave(String query, int limit) async {
    final uri = Uri.parse('https://search.brave.com/search').replace(
      queryParameters: {'q': query, 'source': 'web'},
    );
    final res = await http
        .get(uri, headers: {'User-Agent': _uaDesktop})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final html = utf8.decode(res.bodyBytes);
    final hits = <SearchHit>[];
    final starts = RegExp(
      r'<div class="snippet svelte[^"]*" data-pos="\d+" data-type="web"',
    ).allMatches(html).map((m) => m.start).toList();
    for (var i = 0; i < starts.length && hits.length < limit; i++) {
      final end =
          i + 1 < starts.length ? starts[i + 1] : html.length;
      final block = html.substring(starts[i], end);
      final link = RegExp(r'<a href="(https?://[^"]+)"').firstMatch(block);
      final title = RegExp(
        r'class="title search-snippet-title[^"]*"[^>]*title="([^"]+)"',
      ).firstMatch(block);
      final snip = RegExp(
        r'class="content desktop-default-regular[^"]*">(.*?)</div>',
        dotAll: true,
      ).firstMatch(block);
      final url = link?.group(1) ?? '';
      if (url.isEmpty) continue;
      hits.add(SearchHit(
        title: _stripTags(title?.group(1) ?? ''),
        url: url,
        snippet: _stripTags(snip?.group(1) ?? ''),
      ));
    }
    return hits;
  }

  /// Yahoo (HTML): блоки compTitle, реальный URL спрятан в RU= параметре
  /// редиректа r.search.yahoo.com. Заголовки местами в HTML-сущностях —
  /// вырезаем их, при пустом заголовке берём домен.
  static Future<List<SearchHit>> _yahoo(String query, int limit) async {
    final uri = Uri.parse('https://search.yahoo.com/search').replace(
      queryParameters: {'p': query, 'ei': 'UTF-8'},
    );
    final res = await http
        .get(uri, headers: {'User-Agent': _uaDesktop})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final html = utf8.decode(res.bodyBytes);
    final hits = <SearchHit>[];
    final blocks =
        RegExp(r'<div class="compTitle[^"]*">.*?</li>', dotAll: true)
            .allMatches(html);
    for (final b in blocks) {
      if (hits.length >= limit) break;
      final block = b.group(0) ?? '';
      final href = RegExp(r'href="(https://r\.search\.yahoo\.com/[^"]+)"')
          .firstMatch(block);
      final title = RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true)
          .firstMatch(block);
      final snip = RegExp(r'class="compText[^"]*"[^>]*>(.*?)</div>',
              dotAll: true)
          .firstMatch(block);
      if (href == null) continue;
      final ru = RegExp(r'RU=([^/]+)').firstMatch(href.group(1) ?? '');
      if (ru == null) continue;
      final url = Uri.decodeComponent(ru.group(1)!);
      var t = _stripTags(title?.group(1) ?? '');
      // HTML-сущности вида &Lcy; не расшифровываем, а вырезаем —
      // заголовок получится урезанным, но ссылка и сниппет остаются.
      t = t.replaceAll(RegExp(r'&[a-zA-Z]+;'), '').trim();
      if (t.isEmpty) t = Uri.tryParse(url)?.host ?? url;
      hits.add(SearchHit(
        title: t,
        url: url,
        snippet: _stripTags(snip?.group(1) ?? ''),
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
        .timeout(const Duration(seconds: 6));

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

  /// Удаление HTML-тегов и комментариев Svelte.
  static String _stripTags(String s) =>
      _clean(s.replaceAll(RegExp(r'<[^>]*>'), ''));
}
