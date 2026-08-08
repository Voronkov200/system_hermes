// «Статья» из ответа поиска: красивый HTML-документ в стиле
// статей Telegram (Telegraph): заголовок, дата, аккуратная типографика,
// источники со ссылками. Сохраняется в SystemHermes/docs/статьи/
// и добавляется в «Документы» как источник.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../agent/file_tools.dart';
import 'docs_service.dart';
import 'search_service.dart';

class ArticleService {
  /// Папки для сохранения: название (для UI) → путь относительно корня.
  static const folders = {
    'Статьи (docs/статьи)': 'docs/статьи',
    'Документы (docs)': 'docs',
    'Корень SystemHermes': '',
  };

  /// Форматы сохранения: ключ → подпись и расширение.
  static const formats = {
    'article': ('Статья HTML', '.html'),
    'pdf': ('PDF', '.pdf'),
    'txt': ('Текст (.txt)', '.txt'),
  };

  /// Сохраняет ответ в выбранном формате и папке, добавляет в модуль
  /// «Документы». Возвращает путь к файлу.
  static Future<String> save(
    WidgetRef ref, {
    required String title,
    required String text,
    required List<SearchHit> sources,
    String format = 'article',
    String folder = 'docs/статьи',
  }) async {
    final now = DateTime.now();
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    final dateStr = '${now.day} ${months[now.month - 1]} ${now.year}';

    final root = await _rootDir();
    final dir = Directory(folder.isEmpty
        ? root.path
        : '${root.path}/${folder.replaceAll('\\', '/')}');
    await dir.create(recursive: true);
    final slug = _slug(title);

    String path;
    switch (format) {
      case 'pdf':
        final rel = folder.isEmpty ? '$slug.pdf' : '$folder/$slug.pdf';
        await FileTools.makePdf(title: title, text: text, outPath: rel);
        path = '${dir.path}/$slug.pdf';
      case 'txt':
        path = '${dir.path}/$slug.txt';
        await File(path).writeAsString(_buildTxt(
          title: title,
          date: dateStr,
          text: text,
          sources: sources,
        ));
      default:
        path = '${dir.path}/$slug.html';
        await File(path).writeAsString(_buildHtml(
          title: title,
          date: dateStr,
          text: text,
          sources: sources,
        ));
    }

    await ref.read(docsProvider.notifier).add(
          title: title,
          sourceType: switch (format) {
            'pdf' => 'pdf',
            'txt' => 'text',
            _ => 'article',
          },
          content: format == 'txt' ? _plainText(text, sources) : text,
          filePath: path,
        );

    return path;
  }

  static String _plainText(String text, List<SearchHit> sources) {
    final sb = StringBuffer(text.trim());
    if (sources.isNotEmpty) {
      sb.write('\n\nИсточники:');
      for (var i = 0; i < sources.length; i++) {
        sb.write('\n[${i + 1}] ${sources[i].title}\n   ${sources[i].url}');
      }
    }
    return sb.toString();
  }

  static String _buildTxt({
    required String title,
    required String date,
    required String text,
    required List<SearchHit> sources,
  }) {
    final sb = StringBuffer()
      ..writeln(title)
      ..writeln(date)
      ..writeln()
      ..writeln(_plainText(text, sources));
    return sb.toString();
  }

  /// Корень файлов Hermes: внешнее хранилище, если доступно.
  static Future<Directory> _rootDir() async {
    const external = '/storage/emulated/0/SystemHermes';
    try {
      final d = Directory(external);
      await d.create(recursive: true);
      final probe = File('${d.path}/.probe');
      await probe.writeAsString('ok');
      await probe.delete();
      return d;
    } catch (_) {
      final appDir = await getApplicationDocumentsDirectory();
      final d = Directory('${appDir.path}/HermesFiles');
      await d.create(recursive: true);
      return d;
    }
  }

  /// Безопасное имя файла.
  static String _slug(String s) {
    final clean = s
        .replaceAll(RegExp(r'[^\wа-яА-ЯёЁ\- ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    if (clean.isEmpty) return 'article';
    return clean.length > 60 ? clean.substring(0, 60) : clean;
  }

  static String _buildHtml({
    required String title,
    required String date,
    required String text,
    required List<SearchHit> sources,
  }) {
    final escapedTitle = _esc(title);
    final sourceLinks = <String>[];
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      sourceLinks.add('[${i + 1}] ${_esc(s.title.isEmpty ? s.url : s.title)}');
    }

    // Цитаты [n] превращаем в ссылки на источники.
    var body = _esc(text);
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      final label = '[${i + 1}]';
      body = body.replaceAll(
        label,
        '<a href="${_esc(s.url)}">$label</a>',
      );
    }
    final paragraphs = body
        .split('\n\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => '<p>${p.replaceAll('\n', '<br>')}</p>')
        .join('\n');

    final sourcesHtml = sources.isEmpty
        ? ''
        : '<div class="sources"><h2>Источники</h2>'
            '${sourceLinks.map((s) => '<div class="src">$s</div>').join('\n')}'
            '</div>';

    return '''<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$escapedTitle</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; background: #faf9f7; color: #1f2328; font-family: Georgia, 'Times New Roman', serif; }
  header { background: linear-gradient(135deg, #14213d, #0e4f4f); color: #fff; padding: 56px 24px; text-align: center; }
  h1 { font-size: 30px; line-height: 1.3; margin: 0 auto 10px; max-width: 720px; font-weight: 700; }
  .date { opacity: .8; font-size: 14px; font-family: -apple-system, Roboto, sans-serif; }
  main { max-width: 680px; margin: 0 auto; padding: 36px 22px 72px; font-size: 17px; line-height: 1.75; }
  p { margin: 0 0 18px; }
  a { color: #0d6e6e; text-decoration: none; border-bottom: 1px solid rgba(13,110,110,.3); }
  .sources { margin-top: 48px; border-top: 1px solid #e3e0da; padding-top: 20px; font-family: -apple-system, Roboto, sans-serif; font-size: 14px; }
  .sources h2 { font-size: 15px; letter-spacing: .5px; text-transform: uppercase; color: #6b675f; margin: 0 0 12px; }
  .src { margin: 8px 0; word-break: break-word; }
  .src a { border-bottom: none; }
  footer { text-align: center; padding: 24px; color: #aaa; font-size: 12px; font-family: -apple-system, Roboto, sans-serif; }
</style>
</head>
<body>
<header>
  <h1>$escapedTitle</h1>
  <div class="date">$date</div>
</header>
<main>
$paragraphs
$sourcesHtml
</main>
<footer>Создано в System: Hermes</footer>
</body>
</html>''';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
