// Модуль «Поиск» (в стиле Morphic/NotebookLM Research):
// вопрос → (Стадия −1: погода/валюты без LLM) → переформулировка запроса →
// поиск (SearXNG/DDG/Bing/Brave/Yahoo/Wikipedia) → фильтрация стоп-доменов +
// ранжирование → чтение страниц-источников → LLM составляет ответ с
// рассуждением и цитатами [n].
//
// Спецификация: разделы 2 (пять стадий), 3 (доработки), 6 (задачи 1–8).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../agent/web_tools.dart';
import '../nbrb_api.dart';
import '../settings_service.dart';
import 'concurrency.dart';
import 'llm.dart';
import 'source_filter.dart';
import 'agent_run.dart';

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

/// Намерение запроса (раздел 4 спецификации): что ищем, насколько свежие
/// данные нужны, нужна ли кросс-проверка — и план исследования.
class SearchIntent {
  final String intent;
  final String freshness; // low | medium | high
  final bool needsMultipleSources;
  final List<String> plan;

  const SearchIntent({
    required this.intent,
    required this.freshness,
    required this.needsMultipleSources,
    required this.plan,
  });
}

/// Обмен «вопрос — ответ» для контекста переформулировки (3.2, задача 6).
typedef ChatTurn = ({String q, String a});

/// Тип кэша (3.3, задача 1): Поиск — 5 минут, Исследование — 24 часа,
/// Стадия −1 (погода/валюты) — 15 минут.
enum _CacheKind { search, research, quick }

class _CacheEntry {
  final DateTime at;
  final SearchAnswer answer;

  _CacheEntry(this.at, this.answer);
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

  // ===================================================================
  // Чтение страниц-источников
  // ===================================================================

  /// Кэш прочитанного текста страниц (URL → текст) на сессию.
  static final Map<String, String> _pageCache = {};

  /// Читает страницу источника; при неудаче — сниппет как запасной
  /// вариант. Результат кэшируется на сессию (максимум 60 страниц).
  static Future<String> _fetchPage(
    SearchHit hit, {
    int maxChars = 6000,
    SearchReporter? reporter,
  }) async {
    final cached = _pageCache[hit.url];
    if (cached != null) return cached;
    try {
      final text =
          await pageLimiter.run(() => WebTools.getPage(hit.url, maxChars: maxChars));
      _pageCache[hit.url] = text;
      if (_pageCache.length > 60) {
        _pageCache.remove(_pageCache.keys.first);
      }
      reporter?.event(
        AgentEventType.sourceOpened,
        'Открываю: ${hit.title.isEmpty ? hit.url : hit.title}',
        sourceUrl: hit.url,
      );
      return text;
    } catch (e) {
      _log('Страница не прочитана: ${hit.url} ($e)');
      reporter?.event(
        AgentEventType.sourceOpened,
        'Страница недоступна: ${hit.title.isEmpty ? hit.url : hit.title}',
        sourceUrl: hit.url,
      );
      final s = hit.snippet.trim().isEmpty ? hit.title.trim() : hit.snippet.trim();
      return 'Содержимое страницы недоступно. Сниппет из выдачи: $s';
    }
  }

  /// Формирует промпт-блок: для каждого источника — заголовок, URL и
  /// прочитанное содержимое страницы (или сниппет при сбое).
  static Future<String> _numberedWithContent(
    List<SearchHit> hits, {
    int maxChars = 6000,
    SearchReporter? reporter,
  }) async {
    final contents = await Future.wait([
      for (final h in hits)
        _fetchPage(h, maxChars: maxChars, reporter: reporter),
    ]);
    final sb = StringBuffer();
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      sb.writeln('[${i + 1}] ${h.title.trim()}');
      sb.writeln('URL: ${h.url}');
      sb.writeln(contents[i].trim());
      sb.writeln();
    }
    return sb.toString().trim();
  }

  // ===================================================================
  // Пул конкурентности (раздел 6, задача 2)
  // ===================================================================

  /// Ограничитель поисковых вызовов (аналог MAX_CONCURRENT_TAVILY = 4).
  static final ConcurrencyLimiter searchLimiter =
      ConcurrencyLimiter(AppConstants.maxConcurrentSearches);

  /// Ограничитель чтения страниц-источников. Отдельный пул: чтение
  /// вызывается и из обычного поиска, и внутри задач searchLimiter
  /// (deep research), общий пул создал бы взаимоблокировку.
  static final ConcurrencyLimiter pageLimiter = ConcurrencyLimiter(4);

  /// Ограничитель вызовов LLM (аналог MAX_CONCURRENT_OPENCODE = 2).
  static final ConcurrencyLimiter llmLimiter =
      ConcurrencyLimiter(AppConstants.maxConcurrentLlm);

  // ===================================================================
  // Кэш результатов (3.3, задача 1)
  // ===================================================================

  static final Map<String, _CacheEntry> _cache = {};

  static String _cacheKey(String q) =>
      q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static Duration _ttlOf(_CacheKind kind) => switch (kind) {
        _CacheKind.search => AppConstants.searchCacheTtl,
        _CacheKind.research =>
          const Duration(hours: AppConstants.researchCacheTtlHours),
        _CacheKind.quick => AppConstants.stageMinusOneCacheTtl,
      };

  static SearchAnswer? _cacheGet(String key, _CacheKind kind) {
    final e = _cache[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _ttlOf(kind)) {
      _cache.remove(key);
      return null;
    }
    return e.answer;
  }

  static void _cachePut(String key, SearchAnswer answer, _CacheKind kind) {
    _cache[key] = _CacheEntry(DateTime.now(), answer);
    if (_cache.length > 100) {
      final oldest = _cache.entries
          .reduce((a, b) => a.value.at.isBefore(b.value.at) ? a : b);
      _cache.remove(oldest.key);
    }
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
  /// Стоп-домены (2.3) отсекаются сразу, до отправки на LLM.
  static Future<List<SearchHit>> searchWeb(
    String query, {
    String? searxngUrl,
    int limit = 6,
  }) async {
    // 0. Свой SearXNG-инстанс из настроек — самый надёжный вариант.
    final custom = (searxngUrl ?? '').trim();
    if (custom.isNotEmpty) {
      try {
        final clean = removeStops(
            await _searxng(custom, query, limit));
        if (clean.isNotEmpty) {
          _log('Провайдер: свой SearXNG (${clean.length})');
          return clean;
        }
      } catch (_) {}
    }
    // 0.5. Последний рабочий HTML-провайдер — ускоряет повторные поиски
    // и обходит временные блокировки.
    final saved = _lastGoodProvider;
    if (saved != null) {
      try {
        final clean = removeStops(await _via(saved, query, limit));
        if (clean.isNotEmpty) {
          _log('Провайдер: $saved (кэш, ${clean.length})');
          return clean;
        }
      } catch (_) {}
    }
    // 1. Публичные SearXNG-инстансы: пока не получим JSON с результатами.
    for (final instance in _searxngInstances) {
      try {
        final clean =
            removeStops(await _searxng(instance, query, limit));
        if (clean.isNotEmpty) {
          _log('Провайдер: $instance (${clean.length})');
          return clean;
        }
      } catch (_) {
        // пробуем следующий инстанс
      }
    }
    // 2-7. HTML-провайдеры по порядку.
    for (final name in _providerOrder) {
      try {
        final clean = removeStops(await _via(name, query, limit));
        if (clean.isNotEmpty) {
          _lastGoodProvider = name;
          _log('Провайдер: $name (${clean.length})');
          return clean;
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
  /// убираются. Затем — фильтрация, ранжирование и топ-[limit] (2.3, 3.7).
  /// Если переписывание упало — ищем как есть.
  static Future<List<SearchHit>> searchWebRewritten(
    Ref ref,
    String query, {
    void Function(String stage)? onStage,
    SearchReporter? reporter,
    int limit = 6,
    List<ChatTurn> history = const [],
  }) async {
    final searxngUrl = ref.read(settingsProvider).searchSearxngUrl;
    // 3.7: длинный вставленный текст обрезаем до ~200 символов
    // перед переформулировкой.
    final trimmed =
        query.trim().length > 200 ? query.trim().substring(0, 200) : query.trim();
    final queries = await _rewriteQueries(ref, trimmed, history: history);
    _log('Переписанные запросы: ${queries.join(' | ')}');
    final all = <SearchHit>[];
    final seen = <String>{};
    for (final q in queries) {
      onStage?.call('Ищу: "$q"');
      reporter?.event(
        AgentEventType.searchQueryStarted,
        'Запрос: "$q"',
        query: q,
      );
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
      reporter?.event(
        AgentEventType.searchQueryStarted,
        'Запрос: "$query"',
        query: query,
      );
      _log('Переписывание не дало результатов — ищу исходную фразу.');
      try {
        final hits =
            await searchWeb(query, searxngUrl: searxngUrl, limit: limit);
        for (final h in hits) {
          if (seen.add(h.url)) all.add(h);
        }
      } catch (e) {
        _log('Провал: $e');
        rethrow;
      }
    }
    reporter?.event(
      AgentEventType.searchResultsReceived,
      'Получено ${all.length} результатов',
      description: all.take(8).map((h) => h.title).join('\n'),
    );
    // Фильтрация и ранжирование перед синтезом (2.3, 2.5, 3.7):
    // стоп-домены убраны, дубли схлопнуты по URL, остаются только
    // релевантные, максимум [limit]. Каждый источник получает вердикт
    // с причиной — его видно в журнале агента (раздел 10).
    final before = all.length;
    final verdicts = judgeSources(all, query);
    final filtered = verdicts
        .where((v) => v.kept)
        .take(limit)
        .map((v) => v.hit)
        .toList();
    for (final v in verdicts) {
      final source = AgentSource(
        hit: v.hit,
        status: v.kept ? SourceStatus.found : SourceStatus.rejected,
        score: v.score,
        reason: v.reason,
      );
      reporter?.source(source);
      reporter?.event(
        v.kept
            ? AgentEventType.sourceSelected
            : AgentEventType.sourceRejected,
        v.kept ? 'Источник: ${v.hit.title}' : 'Отброшен: ${v.hit.title}',
        description: v.reason,
        sourceUrl: v.hit.url,
      );
    }
    _log('Ранжирование: $before → ${filtered.length} '
        '(стопы/дубли убраны)');
    reporter?.event(
      AgentEventType.searchResultsReceived,
      'Отобрано ${filtered.length} из $before источников',
    );
    return filtered;
  }

  /// LLM переписывает вопрос в короткие поисковые запросы (2.3, 3.2,
  /// задача 6): дата, язык вопроса, год/месяц для актуальных тем,
  /// без уточнений и рассуждений; температура ≈0.1; резерв — исходный
  /// вопрос.
  static Future<List<String>> _rewriteQueries(
    Ref ref,
    String query, {
    List<ChatTurn> history = const [],
  }) async {
    final today = _todayStr();
    var historyText = '';
    if (history.isNotEmpty) {
      historyText = '\n\nПоследние обмены в этой сессии:\n'
          '${history.take(3).map((e) => 'Вопрос: ${e.q}\nОтвет: ${e.a}').join('\n\n')}'
          '\n\nЕсли текущий вопрос ссылается на предыдущий контекст '
          '(местоимения, сокращённые уточнения) — учти это при '
          'формулировке поисковых запросов.';
    }
    try {
      final raw = await llmLimiter.run(() => retry(
            () => llmComplete(
              ref,
              system: 'Ты — эксперт по поисковым запросам. Сегодня $today. '
                  'Преврати вопрос пользователя в 1-3 конкретных поисковых '
                  'запроса на языке вопроса, по одному на строку, без '
                  'нумерации и кавычек. Каждый запрос — отдельный ракурс '
                  'темы, 3-8 слов, фактологичный. Для актуальных тем '
                  '(погода, новости, курсы валют) добавляй текущий год/'
                  'месяц. Запрещено: уточняющие вопросы, пояснения, '
                  'рассуждения. Ответ — только сами запросы.$historyText',
              user: 'Вопрос: $query',
              maxTokens: 200,
              temperature: 0.1,
              timeoutSeconds: 60,
            ),
            onRetry: (a, e) => _log('Retry переформулировки ($a): $e'),
          ));
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

  // ===================================================================
  // Полный цикл «Поиска» (пять стадий + Стадия −1)
  // ===================================================================

  /// Полный цикл: Стадия −1 → анализ намерения → план → переформулировка →
  /// веб-поиск → фильтрация → чтение страниц → синтез → проверка ответа.
  /// При отсутствии источников LLM не вызывается.
  static Future<SearchAnswer> ask(
    Ref ref,
    String query, {
    void Function(String stage)? onStage,
    List<ChatTurn> history = const [],
    SearchReporter? reporter,
  }) async {
    _gateInput(query);
    final q = query.trim();
    final cacheKey = _cacheKey(q);

    // Стадия −1 (3.6, задача 8): погода/курсы валют — прямые API без LLM.
    onStage?.call('Проверяю типовые запросы…');
    final cachedQuick = _cacheGet(cacheKey, _CacheKind.quick);
    if (cachedQuick != null) {
      _log('Стадия −1: из кэша (${_ttlOf(_CacheKind.quick).inMinutes} мин).');
      return cachedQuick;
    }
    final quick = await _stageMinusOne(ref, q);
    if (quick != null) {
      _log('Стадия −1: быстрый ответ без LLM.');
      _cachePut(cacheKey, quick, _CacheKind.quick);
      return quick;
    }

    // Кэш идентичных запросов (3.3).
    final cached = _cacheGet(cacheKey, _CacheKind.search);
    if (cached != null) {
      _log('Кэш Поиска: мгновенный ответ '
          '(${cached.sources.length} источников).');
      return cached;
    }

    // Тумблер «Не искать в интернете» (3.12, 5.1.9).
    if (ref.read(settingsProvider).searchOffline) {
      _log('Офлайн-режим: веб-поиск пропущен, отвечаю сам.');
      onStage?.call('Отвечаю без интернета…');
      return SearchAnswer(text: await _offlineAnswer(ref, q), sources: const []);
    }

    // Этап 1: анализ намерения + план поиска (разделы 4-5 спецификации).
    final t0 = DateTime.now();
    reporter?.phase(AgentPhase.analyzing);
    reporter?.event(
      AgentEventType.searchPlanCreated,
      'Анализирую запрос',
      query: q,
    );
    onStage?.call('Анализирую запрос…');
    final intent = await _analyzeIntent(ref, q, history: history);
    final plan = intent.plan;
    reporter?.phase(AgentPhase.planning);
    reporter?.event(
      AgentEventType.searchPlanCreated,
      'План из ${plan.length} шаг${_plural(plan.length)}',
      description: plan.map((p) => '• $p').join('\n'),
    );
    reporter?.plan(plan);
    onStage?.call('Планирую поиск…');

    // Стадии 1–3.
    reporter?.phase(AgentPhase.searching);
    final hits = await searchWebRewritten(
      ref,
      q,
      onStage: onStage,
      reporter: reporter,
      history: history,
    );
    _log('Поиск: ${DateTime.now().difference(t0).inSeconds}с.');

    // Критическое правило (2.5): ноль источников — без вызова LLM.
    if (hits.isEmpty) {
      _log('Источников после фильтрации: 0 — LLM не вызывается.');
      const answer = SearchAnswer(
        text: 'Не удалось найти релевантные источники по вашему запросу. '
            'Попробуйте переформулировать вопрос или уточнить детали.',
        sources: [],
      );
      _cachePut(cacheKey, answer, _CacheKind.search);
      return answer;
    }

    // Стадия 4: чтение страниц-источников и синтез с рассуждением.
    reporter?.phase(AgentPhase.openingSources);
    onStage?.call('Читаю страницы-источники…');
    final content = await _numberedWithContent(
      hits,
      maxChars: 6000,
      reporter: reporter,
    );
    reporter?.event(
      AgentEventType.factExtracted,
      'Прочитано ${hits.length} страниц',
      description: hits.map((h) => h.title).take(6).join('\n'),
    );
    reporter?.phase(AgentPhase.synthesizing);
    reporter?.event(AgentEventType.synthesisStarted, 'Составляю ответ…');
    onStage?.call('Составляю ответ…');
    final t1 = DateTime.now();
    var text = await _synthesize(ref, q, hits, content: content);
    if (text == _fallbackPrefix) {
      _log('Синтез упал — резервный ответ из сниппетов.');
    }
    _log('Синтез: ${DateTime.now().difference(t1).inSeconds}с.');

    // Этап 5: проверка ответа — каждая цитата указывает на реальный
    // источник (раздел 17 спецификации).
    reporter?.phase(AgentPhase.verifying);
    reporter?.event(AgentEventType.finalAnswerCreated, 'Проверяю ответ…');
    text = await _verifyCitations(
      ref,
      query: q,
      hits: hits,
      text: text,
      maxRepairs: 1,
    );
    reporter?.event(AgentEventType.finalAnswerCreated, 'Готово');
    for (final h in hits) {
      reporter?.source(AgentSource(
        hit: h,
        status: SourceStatus.used,
        opened: true,
      ));
    }

    final answer = SearchAnswer(text: text, sources: hits);
    _cachePut(cacheKey, answer, _CacheKind.search);
    return answer;
  }

  static String _plural(int n) {
    final m = n % 10;
    final h = n % 100;
    if (m == 1 && h != 11) return '';
    if (m >= 2 && m <= 4 && (h < 12 || h > 14)) return 'а';
    return 'ов';
  }

  /// Намерение запроса (раздел 4 спецификации): тип, свежесть, нужна ли
  /// проверка по нескольким источникам — и план поиска (раздел 5).
  static Future<SearchIntent> _analyzeIntent(
    Ref ref,
    String query, {
    List<ChatTurn> history = const [],
  }) async {
    final today = _todayStr();
    var historyText = '';
    if (history.isNotEmpty) {
      historyText = '\n\nПоследние обмены в этой сессии:\n'
          '${history.take(3).map((e) => 'Вопрос: ${e.q}\nОтвет: ${e.a}').join('\n\n')}'
          '\n\nЕсли текущий вопрос ссылается на предыдущий контекст — '
          'учитывай это при анализе и формулировке шагов плана.';
    }
    const fallback = SearchIntent(
      intent: 'generic',
      freshness: 'medium',
      needsMultipleSources: true,
      plan: [
        'Найти актуальные источники по запросу',
        'Сравнить данные из нескольких источников',
        'Сформировать ответ с цитатами',
      ],
    );
    try {
      final raw = await llmLimiter.run(() => retry(
            () => llmComplete(
              ref,
              system: 'Ты — планировщик поискового агента. Сегодня $today. '
                  'Проанализируй вопрос пользователя и верни СТРОГО один '
                  'JSON-объект без пояснений:\n'
                  '{\n'
                  ' "intent": "краткий тип намерения на русском",\n'
                  ' "freshness": "low|medium|high",\n'
                  ' "needs_multiple_sources": true|false,\n'
                  ' "plan": ["шаг 1", "шаг 2", "шаг 3"]\n'
                  '}\n'
                  'План — 2-4 конкретных шага исследования: что найти, '
                  'какие типы источников проверить (официальные документы, '
                  'новости, экспертные статьи), как сравнить. '
                  'Если вопрос о текущих событиях/ценах/курсах — freshness '
                  '= high. Если фактологический/учебный — low.$historyText',
              user: 'Вопрос: $query',
              maxTokens: 300,
              temperature: 0.1,
              timeoutSeconds: 60,
            ),
            onRetry: (a, e) => _log('Retry анализа намерения ($a): $e'),
          ));
      final json = _extractJson(raw);
      final planRaw = (json['plan'] as List?) ?? const [];
      final plan = planRaw
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(4)
          .toList();
      if (plan.isEmpty) return fallback;
      return SearchIntent(
        intent: (json['intent'] as String?) ?? 'generic',
        freshness: (json['freshness'] as String?) ?? 'medium',
        needsMultipleSources: json['needs_multiple_sources'] == true,
        plan: plan,
      );
    } catch (e) {
      _log('Анализ намерения не удался: $e');
      return fallback;
    }
  }

  /// Достаёт JSON-объект из ответа модели (может быть в ```json … ```).
  static Map<String, dynamic> _extractJson(String raw) {
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (m == null) return const {};
    try {
      final decoded = jsonDecode(m.group(0)!);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const {};
  }

  /// Проверка ответа (раздел 17): каждый [n] указывает на реальный
  /// источник. При битых цитатах — один вызов на исправление.
  static Future<String> _verifyCitations(
    Ref ref, {
    required String query,
    required List<SearchHit> hits,
    required String text,
    int maxRepairs = 1,
  }) async {
    final broken = <String>[];
    for (final m in RegExp(r'\[(\d{1,2})\]').allMatches(text)) {
      final n = int.tryParse(m.group(1) ?? '') ?? 0;
      if (n < 1 || n > hits.length) broken.add(m.group(0)!);
    }
    if (broken.isEmpty || maxRepairs <= 0 || hits.isEmpty) return text;
    _log('Проверка: битые цитаты ${broken.join(', ')} — исправляю.');
    try {
      final fixed = await llmLimiter.run(() => retry(
            () => llmComplete(
              ref,
              system: 'Ты — редактор. В ответе ниже номера источников [n] '
                  'указывают на список из ${hits.length} источников. '
                  'Исправь битые номера ${broken.join(', ')}: замени их на '
                  'ближайший корректный номер от 1 до ${hits.length}, '
                  'соответствующий источнику по теме. Верни исправленный '
                  'текст целиком, без пояснений.',
              user: 'Вопрос: $query\n\nОтвет:\n$text',
              maxTokens: 2600,
              timeoutSeconds: 120,
            ),
            onRetry: (a, e) => _log('Retry исправления цитат ($a): $e'),
          ));
      return fixed.trim().isEmpty ? text : fixed.trim();
    } catch (e) {
      _log('Исправление цитат не удалось: $e');
      return text;
    }
  }

  static const _fallbackPrefix = 'По запросу';

  /// Стадия 4: LLM отвечает только по прочитанным страницам с цитатами
  /// [n] в стиле ChatGPT: суть → рассуждение по пунктам → вывод;
  /// retry на 429/5xx; при неудаче — резервный ответ из сниппетов.
  static Future<String> _synthesize(
    Ref ref,
    String query,
    List<SearchHit> hits, {
    String? content,
  }) async {
    final today = _todayStr();
    final material = (content ?? '').trim().isNotEmpty
        ? content!
        : _numbered(hits);    try {
      return await llmLimiter.run(() => retry(
            () => llmComplete(
              ref,
              system: 'Ты — исследовательский ассистент в стиле ChatGPT '
                  'Deep Research. Сегодня $today. Отвечай на вопрос '
                  'пользователя ПО РУССКИ, опираясь ТОЛЬКО на приведённые '
                  'страницы-источники. Структура ответа: '
                  '1) «Суть» — 2-3 предложения; '
                  '2) «Рассуждение» — разбор по пунктам: факты, цифры, '
                  'сравнения, выводы из источников, с маркерами "-"; '
                  '3) «Вывод» — итоговый ответ. '
                  'Каждый факт подкрепляй источником в квадратных скобках: '
                  '[1], [2]. Если вопрос касается текущих событий, а '
                  'материалы устаревшие или не отвечают на вопрос — честно '
                  'скажи об этом и не выдумывай, не выдавай старые данные '
                  'за актуальные. Пиши подробно, но без воды. Не упоминай, '
                  'что у тебя есть список результатов.',
              user: 'Вопрос: $query\n\nСодержимое страниц-источников:\n'
                  '$material',
              maxTokens: 2400,
              timeoutSeconds: 180,
            ),
            onRetry: (a, e) => _log('Retry синтеза ($a): $e'),
          ));
    } catch (e) {
      _log('Синтез не удался: $e');
      return _fallbackFromSnippets(query, hits);
    }
  }

  /// Резервный ответ из сырых сниппетов (2.6, 2.8): показывается, если
  /// LLM вернула пустую строку или упала.
  static String _fallbackFromSnippets(String query, List<SearchHit> hits) {
    final sb = StringBuffer();
    sb.writeln(_fallbackPrefix);
    sb.writeln(' «$query» нашлись следующие материалы (модель не ответила — '
        'показаны сниппеты источников):');
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      final s = h.snippet.trim().isEmpty ? h.title : h.snippet.trim();
      sb.writeln('\n[${i + 1}] ${h.title.trim()}');
      sb.writeln(s);
      sb.writeln(h.url);
    }
    return sb.toString();
  }

  /// Офлайн-ответ: LLM без поиска (3.12).
  static Future<String> _offlineAnswer(Ref ref, String query) async {
    final today = _todayStr();
    try {
      return await llmLimiter.run(() => retry(
            () => llmComplete(
              ref,
              system: 'Ты — ассистент Hermes. Сегодня $today. Отвечай на '
                  'русском, кратко и по делу. Интернет-поиск отключён '
                  'пользователем: отвечай из своих знаний; если не знаешь — '
                  'честно скажи, что не можешь проверить информацию.',
              user: query,
              maxTokens: 800,
              timeoutSeconds: 90,
            ),
            onRetry: (a, e) => _log('Retry офлайн-ответа ($a): $e'),
          ));
    } catch (e) {
      _log('Офлайн-ответ не удался: $e');
      return 'Интернет-поиск отключён, а модель сейчас не отвечает. '
          'Попробуй ещё раз или включи поиск в настройках.';
    }
  }

  /// Форматирование источников для промпта: [n], заголовок, URL, сниппет
  /// (до [maxChars] символов на источник, 2.6).
  static String _numbered(List<SearchHit> hits, {int maxChars = 1000}) {
    final sb = StringBuffer();
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      var snippet = h.snippet.trim().isEmpty
          ? h.title
          : h.snippet.trim().replaceAll('\n', ' ');
      if (snippet.length > maxChars) {
        snippet = '${snippet.substring(0, maxChars)}…';
      }
      sb.writeln('[${i + 1}] ${h.title.trim()}');
      sb.writeln('URL: ${h.url}');
      sb.writeln(snippet);
    }
    return sb.toString();
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

  // ===================================================================
  // Стадия −1: погода и курсы валют (3.6, задача 8)
  // ===================================================================

  /// Эвристика по ключевым словам: «погода/прогноз/градус» + топоним →
  /// Open-Meteo; «курс/доллар/евро/BYN» → API Нацбанка РБ. При
  /// срабатывании конвейер завершается, минуя переформулировку, поиск
  /// и синтез. При неудаче — возвращает null, поиск идёт как обычно.
  static Future<SearchAnswer?> _stageMinusOne(
      Ref ref, String query) async {
    final q = query.toLowerCase();
    final isWeather = [
      'погод', 'прогноз', 'градус', 'температур', 'дожд', 'снег',
      'ветер', 'пасмурн', 'солнечн', 'осадк', 'гроз', 'туман',
    ].any(q.contains);
    final isCurrency = [
      'курс', 'доллар', 'евро', 'валют', 'рубль', 'byn', 'usd',
      'eur', 'юан', 'гривн',
    ].any(q.contains);
    if (isCurrency && !isWeather) {
      try {
        return await _quickCurrency(ref, query);
      } catch (e) {
        _log('Стадия −1 (валюты) не сработала: $e');
        return null;
      }
    }
    if (isWeather) {
      try {
        return await _quickWeather(query);
      } catch (e) {
        _log('Стадия −1 (погода) не сработала: $e');
        return null;
      }
    }
    return null;
  }

  /// Курсы валют через API Нацбанка РБ (кэш Стадии −1 — 15 минут).
  static Future<SearchAnswer> _quickCurrency(
      Ref ref, String query) async {
    final rates = await retry(() => NbrbApi().fetchRates());
    final usd = NbrbApi.rateOf(rates, 'USD');
    final eur = NbrbApi.rateOf(rates, 'EUR');
    final date = rates.isNotEmpty ? rates.first.date : DateTime.now();
    final sb = StringBuffer();
    sb.writeln(
        'Официальный курс Национального банка Республики Беларусь '
        'на ${_fmtDate(date)}:');
    if (usd != null) sb.writeln('- USD: ${usd.toStringAsFixed(3)} BYN');
    if (eur != null) sb.writeln('- EUR: ${eur.toStringAsFixed(3)} BYN');
    sb.writeln();
    sb.writeln('Это официальные курсы НБ РБ; коммерческий курс в банках '
        'и обменниках может отличаться.');
    return SearchAnswer(
      text: sb.toString().trim(),
      sources: const [
        SearchHit(
          title: 'Национальный банк Республики Беларусь — официальные '
              'курсы валют',
          url: 'https://www.nbrb.by/statistics/rates/ratesdaily.asp',
          snippet: 'Официальные курсы белорусского рубля',
        ),
      ],
    );
  }

  /// Погода через Open-Meteo: геокодинг города + прогноз на 3 дня.
  /// Без города (или при сбое) — null, и поиск идёт обычным путём.
  static Future<SearchAnswer?> _quickWeather(String query) async {
    final m = RegExp(r'\bв\s+([А-ЯЁ][а-яё]+)\b').firstMatch(query);
    if (m == null) return null;
    final city = m.group(1);
    if (city == null) return null;
    // Слова-ловушки: «в среду», «в марте», «в этом году»…
    const traps = {
      'понедельник', 'вторник', 'среду', 'среды', 'четверг', 'пятницу',
      'субботу', 'воскресенье', 'январе', 'феврале', 'марте', 'апреле',
      'мае', 'июне', 'июле', 'августе', 'сентябре', 'октябре', 'ноябре',
      'декабре', 'этом', 'этой', 'таком', 'нашем', 'этих',
    };
    if (traps.contains(city.toLowerCase())) return null;

    // Геокодинг (таймаут подключения ~10с).
    final geo = await http
        .get(
          Uri.parse('https://geocoding-api.open-meteo.com/v1/search').replace(
            queryParameters: {
              'name': city,
              'count': '1',
              'language': 'ru',
              'format': 'json',
            },
          ),
          headers: {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 10));
    if (geo.statusCode != 200) throw Exception('HTTP ${geo.statusCode}');
    final geoData =
        jsonDecode(utf8.decode(geo.bodyBytes)) as Map<String, dynamic>;
    final geoResults = geoData['results'] as List? ?? const [];
    if (geoResults.isEmpty) return null;
    final first = (geoResults.first as Map).cast<String, dynamic>();
    final lat = (first['latitude'] as num).toDouble();
    final lon = (first['longitude'] as num).toDouble();
    final geoName = first['name'] as String? ?? city;

    // Прогноз (таймаут ответа ~15с).
    final res = await http
        .get(
          Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
            queryParameters: {
              'latitude': '$lat',
              'longitude': '$lon',
              'current': 'temperature_2m,weather_code,wind_speed_10m',
              'daily': 'weather_code,temperature_2m_max,temperature_2m_min',
              'timezone': 'auto',
              'forecast_days': '3',
            },
          ),
          headers: {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final current =
        (data['current'] as Map? ?? const {}).cast<String, dynamic>();
    final daily =
        (data['daily'] as Map? ?? const {}).cast<String, dynamic>();
    final times = (daily['time'] as List? ?? const []).cast<String>();
    final codes = (daily['weather_code'] as List? ?? const []).cast<num>();
    final maxT =
        (daily['temperature_2m_max'] as List? ?? const []).cast<num>();
    final minT =
        (daily['temperature_2m_min'] as List? ?? const []).cast<num>();

    final sb = StringBuffer();
    sb.writeln('Погода в $geoName (Open-Meteo):');

    final curTemp = current['temperature_2m'];
    if (curTemp is num) {
      final wc = (current['weather_code'] as num?)?.toInt() ?? 0;
      final wind = (current['wind_speed_10m'] as num?)?.toDouble();
      sb.writeln('- Сейчас: ${_weatherDesc(wc)}, '
          '${curTemp.toStringAsFixed(1)}°C'
          '${wind == null ? '' : ', ветер ${wind.round()} км/ч'}');
    }

    const dayLabels = {
      0: 'Сегодня',
      1: 'Завтра',
      2: 'Послезавтра',
    };
    for (var i = 0; i < times.length && i < 3; i++) {
      final wc = i < codes.length ? codes[i].toInt() : 0;
      final tmax = i < maxT.length ? maxT[i].toDouble() : null;
      final tmin = i < minT.length ? minT[i].toDouble() : null;
      final label = dayLabels[i] ?? times[i];
      sb.writeln('- $label: ${_weatherDesc(wc)}'
          '${tmin == null || tmax == null ? '' : ' '
          '${tmin.toStringAsFixed(0)}…${tmax.toStringAsFixed(0)}°'}');
    }
    sb.writeln();
    sb.writeln('Прогноз автоматический, по данным Open-Meteo. Для '
        'почасового прогноза открой источник.');

    return SearchAnswer(
      text: sb.toString().trim(),
      sources: [
        SearchHit(
          title: 'Open-Meteo — прогноз погоды в $geoName',
          url: 'https://open-meteo.com/',
          snippet: 'Бесплатный прогноз погоды без ограничений',
        ),
      ],
    );
  }

  /// Описание кода погоды WMO на русском.
  static String _weatherDesc(int code) {
    const map = {
      0: 'ясно',
      1: 'преимущественно ясно',
      2: 'переменная облачность',
      3: 'пасмурно',
      45: 'туман',
      48: 'изморозь',
      51: 'лёгкая морось',
      53: 'морось',
      55: 'сильная морось',
      56: 'лёгкая ледяная морось',
      57: 'ледяная морось',
      61: 'небольшой дождь',
      63: 'дождь',
      65: 'сильный дождь',
      66: 'лёгкий ледяной дождь',
      67: 'ледяной дождь',
      71: 'небольшой снег',
      73: 'снег',
      75: 'сильный снег',
      77: 'снежная крупа',
      80: 'небольшой ливень',
      81: 'ливень',
      82: 'сильный ливень',
      85: 'снегопад',
      86: 'сильный снегопад',
      95: 'гроза',
      96: 'гроза с градом',
      99: 'сильная гроза с градом',
    };
    return map[code] ?? 'облачно';
  }

  // ===================================================================
  // Глубокое исследование (раздел 4): тема → подвопросы → параллельный
  // поиск → резюме → отчёт с цитатами [n].
  // ===================================================================

  /// Глубокое исследование (стиль Deep Research): декомпозиция на 3-7
  /// подвопросов → параллельный поиск через пул конкурентности → сжатые
  /// резюме → финальный отчёт с пометкой достоверности (задачи 2-4).
  static Future<SearchAnswer> deepResearch(
    Ref ref,
    String query, {
    void Function(String stage)? onStage,
    List<ChatTurn> history = const [],
    SearchReporter? reporter,
  }) async {
    _gateInput(query);
    final q = query.trim();
    final cacheKey = _cacheKey(q);

    // Задача 1: единый TTL кэша исследований (24 часа).
    final cached = _cacheGet(cacheKey, _CacheKind.research);
    if (cached != null) {
      _log('Кэш Исследования (TTL ${AppConstants.researchCacheTtlHours}ч): '
          'мгновенный отчёт.');
      return cached;
    }

    final today = _todayStr();

    // Стадия 1: декомпозиция (задача 3 — дедуп подвопросов).
    reporter?.phase(AgentPhase.analyzing);
    reporter?.event(
      AgentEventType.searchPlanCreated,
      'Анализирую тему исследования',
      query: q,
    );
    onStage?.call('Планирую исследование…');
    final plan = await llmLimiter.run(() => retry(
          () => llmComplete(
            ref,
            system: 'Ты — планировщик исследования. Сегодня $today. '
                'Составь 3-7 уточняющих подвопросов по теме пользователя, '
                'по одному на строку, без нумерации и кавычек. Подвопросы '
                'должны покрывать: текущее состояние, причины и контекст, '
                'конкретные примеры и цифры, перспективы и критику. '
                'ВАЖНО: подвопросы не должны пересекаться по содержанию.',
            user: 'Тема исследования: $q',
            maxTokens: 400,
            temperature: 0.2,
            timeoutSeconds: 60,
          ),
          onRetry: (a, e) => _log('Retry декомпозиции ($a): $e'),
        ));
    var subqs = plan
        .split('\n')
        .map((l) => l.trim().replaceAll(RegExp(r'^[-*\d.)\s]+'), ''))
        .where((l) => l.length > 8)
        .take(7)
        .toList();
    subqs = _dedupSubquestions(subqs);
    if (subqs.isEmpty) {
      throw Exception('Не удалось составить план исследования.');
    }
    _log('Подвопросы после дедупликации: ${subqs.length}');
    reporter?.phase(AgentPhase.planning);
    reporter?.event(
      AgentEventType.searchPlanCreated,
      'План: ${subqs.length} направлений',
      description: subqs.map((p) => '• $p').join('\n'),
    );
    reporter?.plan(subqs);

    // Стадия 2: параллельный поиск через пул (задача 2), лимит 5
    // источников на подвопрос после фильтрации; затем — чтение страниц
    // и сжатие в резюме.
    reporter?.phase(AgentPhase.searching);
    final results = await Future.wait([
      for (var i = 0; i < subqs.length; i++)
        searchLimiter.run(() async {
          onStage?.call('Изучаю подвопрос ${i + 1} из ${subqs.length}…');
          reporter?.event(
            AgentEventType.searchQueryStarted,
            'Подвопрос ${i + 1}/${subqs.length}: ${subqs[i]}',
            query: subqs[i],
          );
          try {
            final hits = await retry(
              () => searchWebRewritten(
                ref,
                subqs[i],
                onStage: onStage,
                reporter: reporter,
                limit: AppConstants.maxSources,
              ),
              onRetry: (a, e) =>
                  _log('Retry поиска по подвопросу ${i + 1} ($a): $e'),
            );
            // Стадия 3: чтение страниц (топ-3, чтобы не тянуть 35 страниц)
            // и сжатие в резюме (4.2, 4.6).
            reporter?.phase(AgentPhase.openingSources);
            final content = await _numberedWithContent(
              hits.take(3).toList(),
              maxChars: 5000,
              reporter: reporter,
            );
            reporter?.phase(AgentPhase.extractingEvidence);
            final summary =
                await _summarizeSubquestion(ref, subqs[i], content);
            return (i: i, hits: hits, summary: summary);
          } catch (e) {
            _log('Подвопрос ${i + 1} не обработан: $e');
            return (i: i, hits: <SearchHit>[], summary: '(данные отсутствуют)');
          }
        }),
    ]);
    results.sort((a, b) => a.i.compareTo(b.i));

    final allHits = <SearchHit>[];
    final indexOf = <String, int>{};
    final blocks = StringBuffer();
    for (final r in results) {
      blocks.writeln('Подвопрос: ${subqs[r.i]}');
      blocks.writeln(r.summary);
      _appendSources(blocks, r.hits, allHits, indexOf);
    }
    if (allHits.isEmpty) {
      throw Exception('Поисковые сервисы недоступны — нечего анализировать.');
    }

    // Стадия 3.5: выявление пробелов и добор недостающей информации
    // (стиль ChatGPT Deep Research): LLM смотрит резюме, находит аспекты,
    // по которым данных мало, и возвращает дополнительные запросы.
    reporter?.phase(AgentPhase.checkingConflicts);
    reporter?.event(
      AgentEventType.factExtracted,
      'Собрано фактов по ${results.where((r) => r.summary.isNotEmpty).length} направлениям',
    );
    final gaps = await _findGaps(ref, q, blocks.toString());
    if (gaps.isNotEmpty) {
      reporter?.event(
        AgentEventType.factConflictFound,
        'Обнаружены пробелы в данных',
        description: gaps.map((g) => '• $g').join('\n'),
      );
      reporter?.phase(AgentPhase.additionalSearch);
    }
    for (final g in gaps) {
      onStage?.call('Добираю: "$g"');
      reporter?.event(
        AgentEventType.followUpSearchStarted,
        'Дополнительный поиск: "$g"',
        query: g,
      );
      try {
        final hits = await retry(
          () => searchWebRewritten(
            ref,
            g,
            onStage: onStage,
            reporter: reporter,
            limit: 4,
          ),
          onRetry: (a, e) => _log('Retry добора ($a): $e'),
        );
        if (hits.isEmpty) continue;
        final content = await _numberedWithContent(
          hits.take(3).toList(),
          maxChars: 5000,
          reporter: reporter,
        );
        final summary = await _summarizeSubquestion(ref, g, content);
        blocks.writeln('Подвопрос (добор): $g');
        blocks.writeln(summary);
        _appendSources(blocks, hits, allHits, indexOf);
      } catch (e) {
        _log('Добор не удался: $g ($e)');
      }
    }

    // Стадии 4-5: финальный отчёт с рассуждением + пометка достоверности.
    reporter?.phase(AgentPhase.synthesizing);
    reporter?.event(AgentEventType.synthesisStarted, 'Составляю отчёт…');
    onStage?.call('Составляю отчёт…');
    final report = await llmLimiter.run(() => retry(
          () => llmComplete(
            ref,
            system: 'Ты — аналитик-исследователь в стиле ChatGPT Deep '
                'Research. Сегодня $today. Напиши ПОДРОБНЫЙ '
                'структурированный отчёт по теме пользователя на русском, '
                'используя только приведённые промежуточные резюме по '
                'подвопросам. Структура отчёта: '
                '1) «Суть» — 2-3 предложения; '
                '2) «Рассуждение» — раздел по каждому подвопросу: '
                'факты, цифры, примеры, сравнения, анализ противоречий '
                'между источниками; '
                '3) «Выводы» — итог, перспективы и что осталось неясным. '
                'Каждый факт подкрепляй источником в квадратных скобках: '
                '[1], [2] — номера берутся из списка «Все источники» в '
                'конце. Не выдумывай данные; если информации не хватает — '
                'честно скажи. Не упоминай, что у тебя есть список '
                'результатов.',
            user: 'Тема: $q\n\nПромежуточные резюме по подвопросам:\n'
                '$blocks\n\nВсе источники (глобальная нумерация):\n'
                '${_numbered(allHits)}',
            maxTokens: 4000,
            timeoutSeconds: 300,
          ),
          onRetry: (a, e) => _log('Retry финального отчёта ($a): $e'),
        ));

    // Задача 4: явная пометка предварительности кросс-валидации.
    var text = '$report\n\n'
        '*Предварительная автоматическая проверка на противоречия. '
        'Не является гарантией фактической точности.*';

    // Проверка цитат: номера [n] должны указывать на реальные источники.
    reporter?.phase(AgentPhase.verifying);
    reporter?.event(AgentEventType.finalAnswerCreated, 'Проверяю отчёт…');
    text = await _verifyCitations(
      ref,
      query: q,
      hits: allHits,
      text: text,
      maxRepairs: 1,
    );
    reporter?.event(AgentEventType.finalAnswerCreated, 'Готово');
    for (final h in allHits) {
      reporter?.source(AgentSource(
        hit: h,
        status: SourceStatus.used,
        opened: true,
      ));
    }

    final answer = SearchAnswer(text: text, sources: allHits);
    _cachePut(cacheKey, answer, _CacheKind.research);
    return answer;
  }

  /// Стадия 3 «Исследования»: сжатие контента страниц подвопроса в резюме
  /// 4-6 предложений (4.2). В резюме без [n] — глобальная нумерация
  /// выдаётся в финальном отчёте.
  static Future<String> _summarizeSubquestion(
      Ref ref, String subq, String content) async {
    if (content.trim().isEmpty) return '(данные отсутствуют)';
    try {
      return await llmLimiter.run(() => retry(
            () => llmComplete(
              ref,
              system: 'Ты — исследователь. Сожми контент страниц по '
                  'подвопросу в резюме 4-6 предложений на русском: '
                  'ключевые факты, цифры, даты, имена. Используй только '
                  'данные из контента, не выдумывай. Без ссылок и цитат '
                  'в тексте резюме.',
              user: 'Подвопрос: $subq\n\nКонтент страниц:\n$content',
              maxTokens: 500,
              temperature: 0.2,
              timeoutSeconds: 120,
            ),
            onRetry: (a, e) => _log('Retry резюме ($a): $e'),
          ));
    } catch (e) {
      _log('Резюме не получено: $e');
      return '(контент не прочитан)';
    }
  }

  /// Выявление пробелов (стиль ChatGPT Deep Research): LLM анализирует
  /// собранные резюме и возвращает 1-3 коротких поисковых запроса на
  /// недостающие аспекты; если информации достаточно — пустой список.
  static Future<List<String>> _findGaps(
      Ref ref, String theme, String summaries) async {
    try {
      final raw = await llmLimiter.run(() => retry(
            () => llmComplete(
              ref,
              system: 'Ты — критичный аналитик Deep Research. Изучи '
                  'собранные резюме по теме. Определи, какие 1-3 важных '
                  'аспекта не раскрыты или раскрыты слабо, и сформулируй '
                  'их как короткие поисковые запросы (3-8 слов), по одному '
                  'на строку, без нумерации и кавычек. Если информации '
                  'достаточно для полного ответа — ответь ровно одним '
                  'словом: ДОСТАТОЧНО.',
              user: 'Тема: $theme\n\nСобранные резюме:\n$summaries',
              maxTokens: 250,
              temperature: 0.2,
              timeoutSeconds: 60,
            ),
            onRetry: (a, e) => _log('Retry выявления пробелов ($a): $e'),
          ));
      if (raw.trim().toUpperCase() == 'ДОСТАТОЧНО') {
        _log('Пробелов не выявлено.');
        return const [];
      }
      final qs = raw
          .split('\n')
          .map((l) => l.trim().replaceAll(RegExp(r'^[-*\d.)\s]+'), ''))
          .where((l) => l.length >= 8 && l.length <= 120)
          .take(3)
          .toList();
      _log('Пробелы: ${qs.isEmpty ? 'не выявлено' : qs.join(' | ')}');
      return qs;
    } catch (e) {
      _log('Выявление пробелов не удалось: $e');
      return const [];
    }
  }

  /// Добавляет источники в общий список (с глобальными номерами) и
  /// печатает их в [blocks], чтобы финальный отчёт ссылался на
  /// реальные номера [n], а не выдумывал их.
  static void _appendSources(
    StringBuffer blocks,
    List<SearchHit> hits,
    List<SearchHit> allHits,
    Map<String, int> indexOf,
  ) {
    final local = <int>[];
    for (final h in hits) {
      var num = indexOf[h.url];
      if (num == null) {
        num = allHits.length + 1;
        indexOf[h.url] = num;
        allHits.add(h);
      }
      local.add(num);
    }
    blocks.writeln('Источники: ${local.map((n) => '[$n]').join(', ')}');
    blocks.writeln();
  }

  /// Задача 3: дедупликация подвопросов — точное совпадение после
  /// нормализации и близкое (пересечение ключевых слов > 60%).
  static List<String> _dedupSubquestions(List<String> subs) {
    String key(String s) {
      final words = s
          .toLowerCase()
          .replaceAll(RegExp(r'[^а-яёa-z0-9 ]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3)
          .toSet();
      return words.join(' ');
    }

    final out = <String>[];
    for (final sub in subs) {
      final k = key(sub);
      if (k.isEmpty) continue;
      var dup = false;
      for (final existing in out) {
        final ek = key(existing);
        if (ek.isEmpty) continue;
        if (k == ek) {
          dup = true;
          break;
        }
        final a = k.split(' ').toSet();
        final b = ek.split(' ').toSet();
        final inter = a.intersection(b).length;
        final union = a.union(b).length;
        if (union > 0 && inter / union > 0.6) {
          dup = true;
          break;
        }
      }
      if (!dup) out.add(sub);
    }
    return out.isEmpty ? subs.take(1).toList() : out;
  }

  // ===================================================================
  // Вспомогательное
  // ===================================================================

  static String _todayStr() {
    final now = DateTime.now();
    return '${now.day} ${_months[now.month - 1]} ${now.year} года';
  }

  static String _fmtDate(DateTime d) {
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  static const _months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

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
