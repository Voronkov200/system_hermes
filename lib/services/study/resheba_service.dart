// Решения заданий с resheba.top (ГДЗ 11 класс).
//
// Сайт используется как внешний справочник: структура ГДЗ загружается
// отдельно, изображения решений — только по запросу и с локальным кэшем.
// Мы не встраиваем содержимое сайта в APK.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../agent/file_tools.dart';

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

class ReshebaService {
  static const _base = 'https://resheba.top';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  /// Идентификатор структуры ГДЗ на resheba.top для поддерживаемых
  /// предметов 11 класса. Названия предметов в приложении могут меняться,
  /// поэтому используем нормализацию и синонимы.
  static String? jsPathFor(String subjectTitle) {
    final t = _normalize(subjectTitle);
    if (t.contains('английск') || t.contains('англiйск') || t.contains('англ')) {
      return 'anglijskij-jazyk-11-klass';
    }
    if (t.contains('алгебр')) return 'algebra-11-klass';
    if (t.contains('геометр')) return 'geom-11-2021';
    if (t.contains('русск') && t.contains('язык')) {
      return 'russkij-jazyk-11-klass-2021';
    }
    if ((t.contains('беларус') || t.contains('белорус')) && t.contains('мов')) {
      return 'belorusskij-jazyk-11-klass';
    }
    if (t.contains('физик')) return 'fizika-11-2021';
    if (t.contains('хими')) return 'himija-11-klass';
    if (t.contains('биолог')) return 'biologija-11';
    return null;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('ў', 'у')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<ReshebaBook> loadBook(String subjectTitle) async {
    final js = jsPathFor(subjectTitle);
    if (js == null) {
      throw StateError(
        'Для «$subjectTitle» сейчас нет настроенного источника ГДЗ. '
        'Можно использовать внешний поиск из Hermes.',
      );
    }

    final appDir = await FileTools.root();
    final catalogDir = Directory('${appDir.path}/resheba/catalogs');
    final cachedCatalog = File('${catalogDir.path}/$js.js');
    try {
      final body = await _getText('$_base/answers/$js.js');
      final book = parseBook(body);
      await catalogDir.create(recursive: true);
      await cachedCatalog.writeAsString(body, flush: true);
      return book;
    } catch (_) {
      if (!await cachedCatalog.exists()) rethrow;
      final cached = await cachedCatalog.readAsString();
      return parseBook(cached);
    }
  }

  Future<String> _getText(String url) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': _userAgent, 'Accept': '*/*'},
        ).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          return utf8.decode(res.bodyBytes);
        }
        lastError = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastError = e;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw Exception('resheba.top: не удалось загрузить $url ($lastError)');
  }

  /// Парсинг `var GDZ = {...}`. Допускаются JS-ключи без кавычек и
  /// завершающие запятые, которые встречаются в опубликованных структурах.
  static ReshebaBook parseBook(String js) {
    final start = js.indexOf('{');
    final end = js.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Структура ГДЗ не найдена');
    }

    var body = js.substring(start, end + 1);
    body = body.replaceAllMapped(
      RegExp(r'([\{,])\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*:'),
      (m) => '${m[1]}"${m[2]}":',
    );
    body = body.replaceAll(RegExp(r',\s*([\}])'), r'$1');

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неожиданный формат структуры ГДЗ');
    }

    final rawTree = decoded['tree'];
    if (rawTree is! List || rawTree.isEmpty || rawTree.first is! Map) {
      throw const FormatException('В структуре ГДЗ отсутствует tree');
    }
    final root = (rawTree.first as Map).cast<String, dynamic>();
    final rootFolder = (root['folder'] as String? ?? '').trim();
    final rawChildren = root['childrens'];
    final children = rawChildren is List ? rawChildren : const [];

    final sections = <ReshebaSection>[];
    for (final rawChild in children) {
      if (rawChild is! Map) continue;
      final c = rawChild.cast<String, dynamic>();
      final text = (c['text'] as String? ?? '').trim();
      final folder = (c['folder'] as String? ?? '').trim();
      final numbers = _parseNumbers(c['numbers']);
      if (text.isNotEmpty || folder.isNotEmpty) {
        sections.add(
          ReshebaSection(text: text, folder: folder, numbers: numbers),
        );
      }
    }

    final book = ReshebaBook(
      root: rootFolder,
      maxPhotos: (decoded['maxPhotos'] as num?)?.toInt() ?? 1,
      mixedFormats: decoded['mixedFormats'] == true,
      sections: sections,
    );
    if (book.root.isEmpty ||
        book.sections.isEmpty ||
        book.totalNumbers == 0) {
      throw const FormatException('Структура ГДЗ пуста или повреждена');
    }
    return book;
  }

  static List<int> _parseNumbers(Object? rawValue) {
    final raw = rawValue?.toString().trim() ?? '';
    if (raw.isEmpty) return const [];
    final result = <int>[];
    for (final part in raw.split(',')) {
      final value = part.trim();
      final range = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(value);
      if (range != null) {
        final from = int.parse(range.group(1)!);
        final to = int.parse(range.group(2)!);
        if (to >= from && to - from <= 5000) {
          for (var n = from; n <= to; n++) {
            result.add(n);
          }
        }
      } else {
        final n = int.tryParse(value);
        if (n != null) result.add(n);
      }
    }
    return result.toSet().toList()..sort();
  }

  Future<File> loadPhoto(
    String subjectTitle,
    ReshebaBook book,
    ReshebaSection section,
    int number,
  ) async {
    if (number < 0 || !section.numbers.contains(number)) {
      throw ArgumentError('Номер задания $number отсутствует в выбранном разделе.');
    }
    if (book.root.isEmpty || section.folder.isEmpty) {
      throw const FormatException('Некорректная структура пути решения');
    }

    final appDir = await FileTools.root();
    final cacheDir =
        Directory('${appDir.path}/resheba/${book.root}/${section.folder}');
    await cacheDir.create(recursive: true);

    final exts = <String>['png'];
    if (book.mixedFormats) exts.add('jpg');

    for (final ext in exts) {
      final cached = File('${cacheDir.path}/$number.$ext');
      if (await cached.exists() && await _isImageFile(cached)) return cached;
      if (await cached.exists()) await cached.delete();
    }

    Object? lastError;
    for (final ext in exts) {
      final url = solutionUrl(book, section, number, extension: ext);
      try {
        final res = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': _userAgent, 'Accept': 'image/avif,image/webp,image/*,*/*'},
        ).timeout(const Duration(seconds: 25));
        if (res.statusCode == 200 && _isImageResponse(res)) {
          final file = File('${cacheDir.path}/$number.$ext');
          await file.writeAsBytes(res.bodyBytes, flush: true);
          return file;
        }
        lastError = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Не удалось загрузить решение №$number ($lastError)');
  }

  static String solutionUrl(
    ReshebaBook book,
    ReshebaSection section,
    int number, {
    String extension = 'png',
  }) {
    return '$_base/${book.root}/${section.folder}/$number.$extension';
  }

  static bool _isImageResponse(http.Response response) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    return contentType.startsWith('image/') &&
        _hasImageSignature(response.bodyBytes);
  }

  static Future<bool> _isImageFile(File file) async {
    if (!await file.exists() || await file.length() < 4) return false;
    final bytes = await file.openRead(0, 12).fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
    return _hasImageSignature(bytes);
  }

  static bool _hasImageSignature(List<int> bytes) {
    final png = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final jpeg = bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    return png || jpeg;
  }
}
