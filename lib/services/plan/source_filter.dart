// Фильтрация и ранжирование результатов поиска (спецификация: разделы 2.3,
// 3.7.1–3.7.2, 3.8, задачи 1 и 7):
// стоп-домены → дедупликация по нормализованному URL → очки ранжирования →
// лимит источников перед синтезом. Применяется в обоих модулях («Поиск» и
// «Исследование») до отправки результатов в LLM.

import 'search_service.dart';

/// Стоп-домены (2.2): поисковики-агрегаторы, «пустышки» и мусор, которые
/// никогда не должны попадать в ответ. Сравнение по хосту с учётом
/// поддоменов.
const List<String> stopDomains = [
  'pinterest.com', 'instagram.com', 'youtube.com', 'youtu.be',
  'tiktok.com', 'udemy.com', 'quora.com', 'reddit.com', 'yandex.ru',
  'yandex.com', 'mail.ru', 'google.com', 'vk.com', 'ok.ru', 't.me',
  'rutube.ru', 'dzen.ru', 'mirtesen.ru', 'bing.com', 'duckduckgo.com',
  'search.brave.com', 'searx', 'facebook.com', 'capcut.com', 'canva.com',
  'twitch.tv', 'amazon.com', 'aliexpress.com', 'wildberries.ru',
  'ozon.ru', 'avito.ru', 'olx', 'kufar.by', 'wikipedia.mirror',
  'pinterest.ru', 'vk.cc',
];

/// Пути-ловушки внутри в целом нормальных доменов (реклама/обои/магазины).
const List<String> stopPathPatterns = [
  'microsoft.com/store',
  'rewards.',
  '/downloads/',
  'wallpaper',
];

/// «Положительные» домены (2.2): новостные, экспертные, официальные,
/// учебные — получают бонус к рангу.
const List<String> positiveDomains = [
  'wikipedia.org', 'wikidata.org', 'habr.com', 'stackoverflow.com',
  'github.com', 'w3.org', 'mdn', 'developer.mozilla.org',
  'nature.com', 'science.org', 'sciencedirect.com', 'ncbi.nlm.nih.gov',
  'pubmed.ncbi.nlm.nih.gov', 'arxiv.org', 'scholar.google.com',
  'tass.ru', 'ria.ru', 'rbc.ru', 'kommersant.ru', 'vedomosti.ru',
  'forbes.ru', 'interfax.by', 'belta.by', 'onliner.by', 'sputnik.by',
  'sb.by', 'minsknews.by', 'gov.by', 'minfin.gov.by', 'nbrb.by',
  'banki.ru', 'cbr.ru', 'open-meteo.com', 'gismeteo.ru',
  'stanford.edu', 'mit.edu', 'ox.ac.uk', 'harvard.edu',
  'economist.com', 'reuters.com', 'apnews.com', 'bbc.com', 'dw.com',
  'euronews.com', 'news.yandex.ru',
];

/// Спорные домены (2.3): личные блоги, форумы, агрегаторы объявлений,
/// короткие видео — штраф к рангу, но не полный запрет.
const List<String> disputedDomains = [
  'pikabu.ru', 'livejournal.com', 'blogspot.com', 'medium.com',
  'teletype.in', 'twitter.com', 'x.com', 'whatsapp.com',
  'telegram.org', 'vc.ru', 'dtf.ru', 'zen.yandex',
];

/// Приоритетные белорусские домены (3.8, задача 7): получают
/// дополнительный бонус как preferred_domains в конфигурации запроса.
const List<String> preferredDomains = [
  'tut.by', 'onliner.by', 'sputnik.by', 'belta.by', 'sb.by',
  'minsknews.by', 'interfax.by', 'neg.by', 'ctv.by', 'ont.by',
  'nn.by', 'belta.by', 'moyby.com',
];

/// Нормализация URL для дедупликации: без протокола, www, query, якорей
/// и конечного слэша.
String normalizeUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return url.trim().toLowerCase();
  var host = u.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  final path = u.path.toLowerCase().replaceAll(RegExp(r'/+$'), '');
  return host + path;
}

String _hostOf(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return url.toLowerCase();
  return u.host.toLowerCase();
}

bool _hostMatches(String host, String suffix) {
  final s = suffix.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (host == s) return true;
  return host.endsWith('.$s');
}

/// Запрещён ли URL (стоп-домен или путь-ловушка).
bool isStopUrl(String url) {
  if (isPositiveUrl(url)) return false;
  final host = _hostOf(url);
  for (final s in stopDomains) {
    if (_hostMatches(host, s)) return true;
  }
  final lower = url.toLowerCase();
  for (final p in stopPathPatterns) {
    if (lower.contains(p)) return true;
  }
  return false;
}

/// «Положительный» домен: новостной/экспертный/официальный/учебный.
bool isPositiveUrl(String url) {
  final host = _hostOf(url);
  for (final s in positiveDomains) {
    if (_hostMatches(host, s)) return true;
  }
  return false;
}

/// Спорный домен.
bool isDisputedUrl(String url) {
  final host = _hostOf(url);
  for (final s in disputedDomains) {
    if (_hostMatches(host, s)) return true;
  }
  return false;
}

/// Приоритетный (белорусский) домен.
bool isPreferredUrl(String url) {
  final host = _hostOf(url);
  for (final s in preferredDomains) {
    if (_hostMatches(host, s)) return true;
  }
  return false;
}

/// Убрать стоп-домены из выдачи сразу, до отправки на LLM (2.3).
List<SearchHit> removeStops(List<SearchHit> hits) =>
    hits.where((h) => !isStopUrl(h.url)).toList();

/// Признак «свежего» результата (3.7.2): текущий год или слова
/// «сегодня/вчера» в сниппете/заголовке → бонус +10.
bool _looksRecent(SearchHit h) {
  final now = DateTime.now();
  final combined = '${h.title} ${h.snippet}';
  if (RegExp(r'\b(20\d{2})\b').hasMatch(combined) &&
      combined.contains('${now.year}')) {
    return true;
  }
  return RegExp(
    r'(сегодня|вчера|на этой неделе|только что|this week|yesterday)',
    caseSensitive: false,
  ).hasMatch(combined);
}

/// Очки ранжирования (3.7.1): title +20, snippet +10, URL +5,
/// положительный домен +20, стоп −1000, спорный −15, свежесть +10,
/// приоритетный белорусский домен +20.
double rankScore(SearchHit h, String query) {
  final qWords = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2)
      .toList();
  if (qWords.isEmpty) qWords.add(query.toLowerCase());
  final title = h.title.toLowerCase();
  final snippet = h.snippet.toLowerCase();
  final url = h.url.toLowerCase();

  var score = 0.0;
  for (final w in qWords) {
    if (title.contains(w)) score += 20;
    if (snippet.contains(w)) score += 10;
    if (url.contains(w)) score += 5;
  }
  if (isStopUrl(h.url)) score -= 1000;
  if (isDisputedUrl(h.url)) score -= 15;
  if (isPositiveUrl(h.url)) score += 20;
  if (isPreferredUrl(h.url)) score += 20;
  if (_looksRecent(h)) score += 10;
  return score;
}

/// Полный конвейер: убрать стопы → дедуп по нормализованному URL →
/// ранжирование → порог релевантности → топ-[limit].
///
/// Порог: оставляем только результаты с положительным сигналом
/// (совпадение по запросу или авторитетный/приоритетный домен) —
/// аналог порога релевантности 0.55 из раздела 2.5.
List<SearchHit> filterAndRank(
  List<SearchHit> hits,
  String query, {
  int limit = 5,
}) {
  return judgeSources(hits, query)
      .where((v) => v.kept)
      .take(limit)
      .map((v) => v.hit)
      .toList();
}

/// Вердикт по источнику: оценка, взят ли в работу, причина (раздел 9-10
/// спецификации: relevance/authority/freshness → source_score).
class SourceVerdict {
  final SearchHit hit;
  final double score;
  final bool kept;
  final String reason;

  const SourceVerdict({
    required this.hit,
    required this.score,
    required this.kept,
    required this.reason,
  });
}

/// Оценивает каждый источник (без лимита): стоп-домены, дедуп, очки,
/// порог релевантности и понятная причина решения для журнала агента.
List<SourceVerdict> judgeSources(List<SearchHit> hits, String query) {
  final out = <SourceVerdict>[];
  final seen = <String>{};
  for (final h in hits) {
    if (isStopUrl(h.url)) {
      out.add(SourceVerdict(
        hit: h,
        score: -1000,
        kept: false,
        reason: 'Стоп-домен — запрещён политикой поиска',
      ));
      continue;
    }
    final key = normalizeUrl(h.url);
    if (key.isEmpty) continue;
    if (!seen.add(key)) {
      out.add(SourceVerdict(
        hit: h,
        score: -1,
        kept: false,
        reason: 'Дублирует более качественный источник',
      ));
      continue;
    }
    final score = rankScore(h, query);
    out.add(SourceVerdict(
      hit: h,
      score: score,
      kept: score >= 5,
      reason: _reasonOf(h, score),
    ));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

String _reasonOf(SearchHit h, double score) {
  if (isPreferredUrl(h.url)) return 'Приоритетный белорусский источник';
  if (isPositiveUrl(h.url)) return 'Авторитетный/официальный источник';
  if (score >= 40) return 'Напрямую отвечает на запрос';
  if (score >= 15) return 'Частично отвечает на запрос';
  if (score >= 5) return 'Умеренная релевантность';
  return 'Низкая релевантность запросу';
}
