// Решения заданий с resheba.top (ГДЗ 11 класс).
//
// Сайт отдаёт структуру разборов в виде JS-файла (var GDZ = {...}),
// а сами решения — фотографиями по адресу
// /GDZ/<book>/<section>/<number>.png (или .jpg). Модуль скачивает
// структуру, а фото — по требованию с кэшем на диск.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../agent/file_tools.dart';

/// Раздел (глава/параграф) с номерами заданий.
class ReshebaSection {
  final String text;
  final String folder;
  final List<int> numbers;

  const ReshebaSection({
    required this.text,
    required this.folder,
    required this.numbers,
  });
}

/// Книга ГДЗ: корневая папка + разделы.
class ReshebaBook {
  final String root;
  final int maxPhotos;
  final bool mixedFormats;
  final List<ReshebaSection> sections;

  const ReshebaBook({
    required this.root,
    required this.maxPhotos,
    required this.mixedFormats,
    required this.sections,
  });

  int get totalNumbers =>
      sections.fold(0, (sum, s) => sum + s.numbers.length);
}

/// Сервис ГДЗ resheba.top.
class ReshebaService {
  static const _base = 'https://resheba.top';

  /// JS-файл со структурой решений для предмета (или null).
  static String? jsPathFor(String subjectTitle) => switch (subjectTitle) {
        'Алгебра' => 'algebra-11-klass',
        'Геометрия' => 'geom-11-2021',
        'Русский язык' => 'russkij-jazyk-11-klass-2021',
        'Беларуская мова' => 'belorusskij-jazyk-11-klass',
        'Английский язык' => 'anglijskij-jazyk-11-klass',
        'Физика' => 'fizika-11-2021',
        'Химия' => 'himija-11-klass',
        _ => null,
      };

  /// Загрузка структуры книги ГДЗ.
  Future<ReshebaBook> loadBook(String subjectTitle) async {
    final js = jsPathFor(subjectTitle);
    if (js == null) {
      throw Exception('Для этого предмета нет решений на resheba.top');
    }
    final res = await http.get(Uri.parse('$_base/answers/$js.js'), headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    });
    if (res.statusCode != 200) {
      throw Exception('resheba.top: HTTP ${res.statusCode}');
    }
    return _parseBook(utf8.decode(res.bodyBytes));
  }

  /// Парсинг `var GDZ = {...}` (ключи без кавычек) в JSON.
  static ReshebaBook _parseBook(String js) {
    final start = js.indexOf('{');
    final end = js.lastIndexOf('}');
    if (start < 0 || end <= start) throw Exception('Не удалось прочитать ГДЗ');
    var body = js.substring(start, end + 1);
    body = body.replaceAllMapped(
        RegExp(r'([\{,])\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*:'),
        (m) => '${m[1]}"${m[2]}":');
    body = body.replaceAll(RegExp(r',\s*([\}])'), r'$1');
    final data = jsonDecode(body) as Map<String, dynamic>;

    final root = (data['tree'] as List).first as Map<String, dynamic>;
    final rootFolder = (root['folder'] as String? ?? '').trim();
    final children = root['childrens'] as List? ?? const [];

    final sections = <ReshebaSection>[];
    for (final child in children) {
      final c = child as Map<String, dynamic>;
      final text = (c['text'] as String? ?? '').trim();
      final folder = (c['folder'] as String? ?? '').trim();
      final numbers = <int>[];
      final raw = (c['numbers'] as String? ?? '').trim();
      for (final part in raw.split(',')) {
        final r = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(part.trim());
        if (r != null) {
          for (var n = int.parse(r.group(1)!); n <= int.parse(r.group(2)!); n++) {
            numbers.add(n);
          }
        } else {
          final n = int.tryParse(part.trim());
          if (n != null) numbers.add(n);
        }
      }
      if (text.isNotEmpty || folder.isNotEmpty) {
        sections.add(ReshebaSection(text: text, folder: folder, numbers: numbers));
      }
    }

    return ReshebaBook(
      root: rootFolder,
      maxPhotos: data['maxPhotos'] as int? ?? 1,
      mixedFormats: data['mixedFormats'] as bool? ?? false,
      sections: sections,
    );
  }

  /// Путь к фото решения с кэшем на диск. Скачивает при первом запросе.
  Future<File> loadPhoto(
    String subjectTitle,
    ReshebaBook book,
    ReshebaSection section,
    int number,
  ) async {
    final appDir = await FileTools.root();
    final cacheDir =
        Directory('${appDir.path}/resheba/${book.root}/${section.folder}');
    await cacheDir.create(recursive: true);

    final exts = <String>['png'];
    if (book.mixedFormats) exts.add('jpg');

    File? cached;
    for (final ext in exts) {
      final f = File('${cacheDir.path}/$number.$ext');
      if (await f.exists()) {
        cached = f;
        break;
      }
    }
    if (cached != null) return cached;

    for (final ext in exts) {
      final url = '$_base/${book.root}/${section.folder}/$number.$ext';
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      });
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        final f = File('${cacheDir.path}/$number.$ext');
        await f.writeAsBytes(res.bodyBytes, flush: true);
        return f;
      }
    }
    throw Exception('Не удалось загрузить решение №$number');
  }
}
