// Веб-инструменты агента: поиск в интернете и чтение страниц.
//
// Поиск: DuckDuckGo (без ключа) + резерв на Wikipedia. Чтение страницы:
// загрузка HTML и извлечение текста.

import 'dart:convert';

import 'package:http/http.dart' as http;

class WebTools {
  static const String _ddgUrl = 'https://html.duckduckgo.com/html/';
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/125.0 Mobile Safari/537.36';

  /// Поиск в интернете, возвращает текст со ссылками и сниппетами.
  static Future<String> search(String query, {int limit = 5}) async {
    final res = await http
        .post(
          Uri.parse(_ddgUrl),
          headers: {'User-Agent': _ua},
          body: {'q': query},
        )
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw Exception('Поиск недоступен: HTTP ${res.statusCode}');
    }
    final html = res.body;
    final results = <String>[];
    final linkRe =
        RegExp(r'class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
            dotAll: true);
    final snipRe =
        RegExp(r'class="result__snippet"[^>]*>(.*?)</(?:a|div)>',
            dotAll: true);
    final links = linkRe.allMatches(html).toList();
    final snips = snipRe.allMatches(html).toList();

    for (var i = 0; i < links.length && results.length < limit; i++) {
      var href = links[i].group(1) ?? '';
      final m = RegExp(r'uddg=([^&]+)').firstMatch(href);
      if (m != null) href = Uri.decodeComponent(m.group(1)!);
      final title = _stripHtml(links[i].group(2) ?? '').trim();
      final snippet = i < snips.length
          ? _stripHtml(snips[i].group(1) ?? '').trim()
          : '';
      if (title.isEmpty && href.isEmpty) continue;
      results.add('$title\n$href\n$snippet');
    }

    if (results.isEmpty) {
      final wiki = await _wikipediaSearch(query, limit);
      return wiki;
    }
    return 'Результаты поиска по «$query»:\n\n${results.join('\n\n')}';
  }

  /// Загрузка страницы и извлечение читаемого текста.
  static Future<String> getPage(String url, {int maxChars = 6000}) async {
    var target = url.trim();
    if (!target.startsWith('http')) target = 'https://$target';
    final res = await http
        .get(
          Uri.parse(target),
          headers: {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('Страница недоступна: HTTP ${res.statusCode}');
    }
    final html = res.body;
    final title = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true)
        .firstMatch(html)
        ?.group(1)
        ?.trim();
    var text = _stripHtml(html);
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > maxChars) text = '${text.substring(0, maxChars)}…';
    final header = title == null ? '' : 'Заголовок: $title\n\n';
    return '$header$text';
  }

  // ------------------------------------------------------- Wikipedia

  static Future<String> _wikipediaSearch(String query, int limit) async {
    final url = Uri.parse('https://ru.wikipedia.org/w/api.php').replace(
      queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': query,
        'format': 'json',
        'utf8': '1',
        'srlimit': '$limit',
        'srprop': 'snippet',
      },
    );
    final res = await http
        .get(url, headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception('Поиск недоступен: HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final items = (data['query']?['search'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (items.isEmpty) return 'Ничего не найдено по запросу «$query».';
    final parts = items.take(limit).map((it) {
      final title = it['title'] as String? ?? '';
      final snippet = _stripHtml(it['snippet'] as String? ?? '');
      return '$title\nhttps://ru.wikipedia.org/wiki/'
          '${Uri.encodeComponent(title).replaceAll('%20', '_')}\n$snippet';
    });
    return 'Результаты поиска по «$query» (Wikipedia):\n\n'
        '${parts.join('\n\n')}';
  }

  /// Удаление HTML-тегов и декодирование сущностей.
  static String _stripHtml(String html) {
    var text = html.replaceAll(RegExp(r'<script[\s\S]*?</script>'), ' ');
    text = text.replaceAll(RegExp(r'<style[\s\S]*?</style>'), ' ');
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    return text;
  }
}
