// Общая конфигурация PDFium для учебников.
//
// Школьные PDF часто используют внешние шрифты (включая математические).
// На Android их нужно явно предоставить PDFium, иначе часть формул и
// специальных символов может рендериться пустой.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

const _bundledMathFontAsset = 'assets/fonts/NotoSansMath-Regular.ttf';
File? _bundledMathFont;

const _androidFontDirectories = <String>[
  '/system/fonts',
  '/product/fonts',
  '/system/product/fonts',
  '/vendor/fonts',
  '/system/vendor/fonts',
];

/// Резервный resolver для PDF, которые ссылаются на отсутствующие Windows/
/// издательские гарнитуры вроде Cambria Math, Symbol или Times New Roman.
/// Он не меняет PDF: только даёт PDFium ближайший локальный Android-шрифт.
class _HermesAndroidFontResolver extends PdfFontResolver {
  _HermesAndroidFontResolver();

  @override
  FutureOr<PdfFontResolution?> resolve(
    PdfFontQuery query,
    PdfFontResolveContext context,
  ) {
    if (!Platform.isAndroid) return null;

    final face = query.face.toLowerCase();
    final isMath = face.contains('math') ||
        face.contains('symbol') ||
        face.contains('cambria') ||
        face.contains('stix') ||
        face.contains('mt extra') ||
        face.startsWith('cm');
    final bundledMath = _bundledMathFont;
    if (isMath && bundledMath != null && bundledMath.existsSync()) {
      return PdfFontResolution.localFontFile(
        fontFilePath: bundledMath.path,
        targetFace: query.face,
        resolvedFace: 'Noto Sans Math',
      );
    }
    final isSerif = face.contains('serif') ||
        face.contains('times') ||
        face.contains('georgia') ||
        face.contains('cambria');
    final isMono = query.isFixed ||
        face.contains('mono') ||
        face.contains('courier');

    final fileNames = <String>[
      if (isMath) ...[
        'NotoSansMath-Regular.ttf',
        'NotoSansSymbols2-Regular.ttf',
        'NotoSansSymbols-Regular.ttf',
      ],
      if (isMono) ...[
        'NotoSansMono-Regular.ttf',
        'RobotoMono-Regular.ttf',
        'DroidSansMono.ttf',
      ],
      if (isSerif) 'NotoSerif-Regular.ttf',
      'NotoSans-Regular.ttf',
      'Roboto-Regular.ttf',
      'NotoSerif-Regular.ttf',
    ];

    for (final directory in _androidFontDirectories) {
      for (final fileName in fileNames) {
        final file = File('$directory/$fileName');
        if (!file.existsSync()) continue;
        return PdfFontResolution.localFontFile(
          fontFilePath: file.path,
          targetFace: query.face,
          resolvedFace: fileName.replaceFirst(RegExp(r'\.(ttf|otf)$'), ''),
        );
      }
    }
    return null;
  }
}

final hermesPdfFontManager = PdfFontManager(
  resolvers: [_HermesAndroidFontResolver()],
);

final _fontAssociations = Expando<PdfFontManagerAssociation>();

/// Подключает fallback-шрифты именно к открытому документу. prepare() сам по
/// себе этого не делает; без association PdfPageView не загружает пропавшие
/// Cambria Math/Symbol/STIX glyphs.
PdfFontManagerAssociation associateHermesPdfFonts(PdfDocument document) {
  final existing = _fontAssociations[document];
  if (existing != null) return existing;
  final association = document.associateFontManager(hermesPdfFontManager);
  _fontAssociations[document] = association;
  return association;
}

Future<File> _materializeBundledMathFont() async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}/pdf_fonts');
  await directory.create(recursive: true);
  final target = File('${directory.path}/NotoSansMath-Regular.ttf');
  final data = await rootBundle.load(_bundledMathFontAsset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (!await target.exists() || await target.length() != bytes.length) {
    await target.writeAsBytes(bytes, flush: true);
  }
  return target;
}

File? _firstAndroidFont(List<String> names) {
  for (final directory in _androidFontDirectories) {
    for (final name in names) {
      final file = File('$directory/$name');
      if (file.existsSync()) return file;
    }
  }
  return null;
}

/// PDFium's own font mapper is global. Регистрируем распространённые имена
/// математических/офисных шрифтов как алиасы к системным Noto/Roboto, чтобы
/// формулы работали и в PdfPageView, и в PdfViewer без отдельной настройки
/// каждого предмета или каждой страницы.
Future<void> _registerAndroidFontAliases(File bundledMath) async {
  final math = bundledMath.existsSync() ? bundledMath : _firstAndroidFont(const [
    'NotoSansMath-Regular.ttf',
    'NotoSansSymbols2-Regular.ttf',
    'NotoSansSymbols-Regular.ttf',
  ]);
  final serif = _firstAndroidFont(const [
    'NotoSerif-Regular.ttf',
    'RobotoSerif-Regular.ttf',
    'Roboto-Regular.ttf',
  ]);
  final sans = _firstAndroidFont(const [
    'NotoSans-Regular.ttf',
    'Roboto-Regular.ttf',
  ]);

  final entry = PdfrxEntryFunctions.instance;
  var registered = false;

  Future<void> addAliases(File? file, Iterable<String> faces) async {
    if (file == null) return;
    for (final face in faces) {
      try {
        await entry.addFontFile(
          face: face,
          filePath: file.path,
          resolvedFace: file.uri.pathSegments.last,
        );
        registered = true;
      } catch (_) {
        // Некоторые Android-сборки запрещают отдельные системные файлы.
        // Остальные алиасы и стандартный font mapper продолжат работать.
      }
    }
  }

  await addAliases(math, const [
    'Cambria Math',
    'CambriaMath',
    'Symbol',
    'SymbolMT',
    'MT Extra',
    'STIX',
    'STIX Math',
    'STIXGeneral',
    'Euclid',
    'Euclid Symbol',
    'MathematicalPi-One',
    'CMSY10',
    'CMEX10',
    'CMMI10',
  ]);
  await addAliases(serif, const [
    'Times New Roman',
    'TimesNewRomanPSMT',
    'Cambria',
    'Georgia',
  ]);
  await addAliases(sans, const [
    'Arial',
    'ArialMT',
    'Helvetica',
    'Calibri',
  ]);

  if (registered) {
    await entry.reloadFonts();
  }
}

Future<void> initializeHermesPdfEngine() async {
  // pdfrxFlutterInitialize асинхронный: PDF нельзя открывать до его завершения.
  await pdfrxFlutterInitialize();

  if (!Platform.isAndroid) {
    await hermesPdfFontManager.prepare();
    return;
  }

  final fontPaths = _androidFontDirectories
      .where((path) => Directory(path).existsSync())
      .toList(growable: false);

  _bundledMathFont = await _materializeBundledMathFont();
  await hermesPdfFontManager.prepare(
    fontPaths: fontPaths.isEmpty ? null : fontPaths,
  );
  await _registerAndroidFontAliases(_bundledMathFont!);
}
