// Общая конфигурация PDFium для учебников.
//
// Школьные PDF часто используют внешние шрифты (включая математические).
// На Android их нужно явно предоставить PDFium, иначе часть формул и
// специальных символов может рендериться пустой.

import 'dart:async';
import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

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
  const _HermesAndroidFontResolver();

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
        face.contains('mt extra');
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
  resolvers: const [_HermesAndroidFontResolver()],
);

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

  await hermesPdfFontManager.prepare(
    fontPaths: fontPaths.isEmpty ? null : fontPaths,
  );
}
