// Решения заданий с resheba.top (ГДЗ 11 класс).
//
// Сайт используется как внешний справочник: структура ГДЗ загружается
// отдельно, изображения решений — по запросу и с локальным кэшем.
// Каталоги и несколько стартовых фото могут готовиться заранее в фоне.
// Мы не встраиваем содержимое сайта в APK.

import 'dart:async';
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
  final String sourceSlug;
  final bool fromCache;

  const ReshebaBook({
    required this.root,
    required this.maxPhotos,
    required this.mixedFormats,
    required this.sections,
    this.sourceSlug = '',
    this.fromCache = false,
  });

  int get totalNumbers =>
      sections.fold(0, (sum, s) => sum + s.numbers.length);
}

class ReshebaService {
  static const _base = 'https://resheba.top';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  // Память и in-flight общие для всех экземпляров сервиса. Экран ГДЗ и
  // фоновый прогрев поэтому не скачивают один и тот же каталог/фото дважды.
  static final Map<String, ReshebaBook> _bookMemory = <String, ReshebaBook>{};
  static final Map<String, Future<ReshebaBook>> _bookInFlight =
      <String, Future<ReshebaBook>>{};
  static final Map<String, Future<File>> _photoInFlight =
      <String, Future<File>>{};

  /// Идентификатор структуры ГДЗ на resheba.top для поддерживаемых
  /// предметов 11 класса. Названия предметов в приложении могут меняться,
  /// поэтому используем нормализацию и синонимы.
  static List<String> jsPathsFor(String subjectTitle) {
    final t = _normalize(subjectTitle);
    if (t.contains('английск') || t.contains('англiйск') || t.contains('англ')) {
      return const ['anglijskij-jazyk-11-klass'];
    }
    if (t.contains('алгебр')) return const ['algebra-11-klass'];
    if (t.contains('геометр')) {
      return const ['geometrija-11-klass', 'geom-11-2021'];
    }
    if (t.contains('русск') && t.contains('язык')) {
      return const [
        'russkij-jazyk-11-klass',
        'russkij-jazyk-11-klass-2021',
      ];
    }
    if ((t.contains('беларус') || t.contains('белорус')) && t.contains('мов')) {
      return const ['belorusskij-jazyk-11-klass'];
    }
    if (t.contains('физик')) {
      return const ['fizika-11-klass', 'fizika-11-2021'];
    }
    if (t.contains('хими')) return const ['himija-11-klass'];
    if (t.contains('биолог')) {
      return const ['biologija-11-klass-dashkov', 'biologija-11'];
    }
    return const [];
  }

  static String? jsPathFor(String subjectTitle) {
    final paths = jsPathsFor(subjectTitle);
    return paths.isEmpty ? null : paths.first;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('ў', 'у')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<ReshebaBook> loadBook(String subjectTitle) {
    final candidates = jsPathsFor(subjectTitle);
    if (candidates.isEmpty) {
      return Future<ReshebaBook>.error(
        StateError(
          'Для «$subjectTitle» сейчас нет настроенного источника ГДЗ. '
          'Можно использовать внешний поиск из Hermes.',
        ),
      );
    }

    // Один и тот же набор кандидатов означает один и тот же решебник — это
    // объединяет, например, две части английского в один сетевой запрос.
    final key = candidates.join('|');
    final memory = _bookMemory[key];
    if (memory != null) return Future<ReshebaBook>.value(memory);
    final active = _bookInFlight[key];
    if (active != null) return active;

    late final Future<ReshebaBook> tracked;
    tracked = _loadBook(subjectTitle, candidates).then((book) {
      _bookMemory[key] = book;
      return book;
    }).whenComplete(() {
      if (identical(_bookInFlight[key], tracked)) {
        _bookInFlight.remove(key);
      }
    });
    _bookInFlight[key] = tracked;
    return tracked;
  }

  Future<ReshebaBook> _loadBook(
    String subjectTitle,
    List<String> candidates,
  ) async {
    final appDir = await FileTools.root();
    final catalogDir = Directory('${appDir.path}/resheba/catalogs');
    Object? lastError;

    // Сначала локальный каталог: после первой подготовки экран ГДЗ открывается
    // без ожидания сети. Если кэша нет/он повреждён — берём свежую структуру.
    for (final slug in candidates) {
      final cachedCatalog = File('${catalogDir.path}/$slug.js');
      if (!await cachedCatalog.exists()) continue;
      try {
        final cached = await cachedCatalog.readAsString();
        final parsed = parseBook(cached, sourceSlug: slug);
        return ReshebaBook(
          root: parsed.root,
          maxPhotos: parsed.maxPhotos,
          mixedFormats: parsed.mixedFormats,
          sections: parsed.sections,
          sourceSlug: parsed.sourceSlug,
          fromCache: true,
        );
      } catch (error) {
        lastError = error;
      }
    }

    for (final slug in candidates) {
      try {
        final body = await _getText('$_base/answers/$slug.js');
        final book = parseBook(body, sourceSlug: slug);
        await catalogDir.create(recursive: true);
        await File('${catalogDir.path}/$slug.js')
            .writeAsString(body, flush: true);
        return book;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(
      'Не удалось открыть каталог решений для «$subjectTitle». '
      'Проверь интернет и повтори. Последняя ошибка: $lastError',
    );
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
  static ReshebaBook parseBook(String js, {String sourceSlug = ''}) {
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
    _collectSections(children, sections);

    final book = ReshebaBook(
      root: rootFolder,
      maxPhotos: (decoded['maxPhotos'] as num?)?.toInt() ?? 1,
      mixedFormats: decoded['mixedFormats'] == true,
      sections: sections,
      sourceSlug: sourceSlug,
    );
    if (book.root.isEmpty ||
        book.sections.isEmpty ||
        book.totalNumbers == 0) {
      throw const FormatException('Структура ГДЗ пуста или повреждена');
    }
    return book;
  }

  static void _collectSections(
    List<dynamic> nodes,
    List<ReshebaSection> output, {
    String parentText = '',
    String parentFolder = '',
  }) {
    for (final rawNode in nodes) {
      if (rawNode is! Map) continue;
      final node = rawNode.cast<String, dynamic>();
      final ownText = (node['text'] as String? ?? '').trim();
      final ownFolder = (node['folder'] as String? ?? '').trim();
      final text = parentText.isEmpty || ownText.isEmpty
          ? '$parentText$ownText'.trim()
          : '$parentText · $ownText';
      final folder = parentFolder.isEmpty || ownFolder.contains('/')
          ? ownFolder
          : ownFolder.isEmpty
              ? parentFolder
              : '$parentFolder/$ownFolder';
      final numbers = _parseNumbers(node['numbers']);
      if (numbers.isNotEmpty && folder.isNotEmpty) {
        output.add(
          ReshebaSection(
            text: text.isEmpty ? 'Задания' : text,
            folder: folder,
            numbers: numbers,
          ),
        );
      }
      final rawChildren = node['childrens'] ?? node['children'];
      if (rawChildren is List && rawChildren.isNotEmpty) {
        _collectSections(
          rawChildren,
          output,
          parentText: text,
          parentFolder: folder,
        );
      }
    }
  }

  static List<int> _parseNumbers(Object? rawValue) {
    if (rawValue is List) {
      final numbers = <int>[];
      for (final value in rawValue) {
        numbers.addAll(_parseNumbers(value));
      }
      return numbers.toSet().toList()..sort();
    }
    final raw = rawValue?.toString().trim() ?? '';
    if (raw.isEmpty) return const [];
    final result = <int>[];
    for (final part in raw.split(',')) {
      final value = part.trim();
      final range = RegExp(r'^(\d+)\s*[-–—]\s*(\d+)$').firstMatch(value);
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

  /// Загружает фото решения и сразу начинает подкачивать соседние номера.
  Future<File> loadPhoto(
    String subjectTitle,
    ReshebaBook book,
    ReshebaSection section,
    int number,
  ) async {
    final file = await _ensurePhoto(subjectTitle, book, section, number);
    _prefetchNeighbors(subjectTitle, book, section, number);
    return file;
  }

  /// Небольшой прогрев для экрана ГДЗ: по одному фото из первых разделов.
  /// Намеренно ограничен, чтобы не скачивать тысячи решений и не занимать
  /// гигабайты памяти без необходимости.
  Future<void> prefetchPreviewPhotos(
    String subjectTitle,
    ReshebaBook book, {
    int limit = 2,
  }) async {
    if (limit <= 0) return;
    final pending = <Future<void>>[];
    for (final section in book.sections) {
      if (section.numbers.isEmpty) continue;
      pending.add(
        _ignoreErrors(
          _ensurePhoto(
            subjectTitle,
            book,
            section,
            section.numbers.first,
          ),
        ),
      );
      if (pending.length >= limit) break;
    }
    await Future.wait(pending);
  }

  Future<File> _ensurePhoto(
    String subjectTitle,
    ReshebaBook book,
    ReshebaSection section,
    int number,
  ) {
    final key = '${book.root}\n${section.folder}\n$number';
    final active = _photoInFlight[key];
    if (active != null) return active;

    late final Future<File> tracked;
    tracked = _loadPhoto(subjectTitle, book, section, number).whenComplete(() {
      if (identical(_photoInFlight[key], tracked)) {
        _photoInFlight.remove(key);
      }
    });
    _photoInFlight[key] = tracked;
    return tracked;
  }

  Future<File> _loadPhoto(
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

    // На сайте встречаются разные форматы даже в каталогах без флага
    // mixedFormats. Проверяем их в предсказуемом порядке.
    final exts = <String>['png', 'jpg', 'jpeg', 'webp'];

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
          headers: {
            'User-Agent': _userAgent,
            'Accept': 'image/avif,image/webp,image/*,*/*',
            'Accept-Language': 'ru-RU,ru;q=0.9,en;q=0.7',
            'Referer': sourcePageUrl(book),
          },
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
    throw Exception(
      'Не удалось загрузить решение №$number для «$subjectTitle» ($lastError)',
    );
  }

  void _prefetchNeighbors(
    String subjectTitle,
    ReshebaBook book,
    ReshebaSection section,
    int number,
  ) {
    final index = section.numbers.indexOf(number);
    if (index < 0) return;
    for (final nextIndex in [index - 1, index + 1]) {
      if (nextIndex < 0 || nextIndex >= section.numbers.length) continue;
      unawaited(
        _ignoreErrors(
          _ensurePhoto(
            subjectTitle,
            book,
            section,
            section.numbers[nextIndex],
          ),
        ),
      );
    }
  }

  static Future<void> _ignoreErrors(Future<dynamic> future) async {
    try {
      await future;
    } catch (_) {
      // Prefetch — best effort. Ошибку нужного фото покажет основной экран.
    }
  }

  static String solutionUrl(
    ReshebaBook book,
    ReshebaSection section,
    int number, {
    String extension = 'png',
  }) {
    return '$_base/${book.root}/${section.folder}/$number.$extension';
  }

  static String sourcePageUrl(ReshebaBook book) => book.sourceSlug.isEmpty
      ? '$_base/gdz/11-klass'
      : '$_base/${book.sourceSlug}';

  static bool _isImageResponse(http.Response response) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    return (contentType.startsWith('image/') ||
            contentType.contains('octet-stream')) &&
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
    final webp = bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return png || jpeg || webp;
  }
}
