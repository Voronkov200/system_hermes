// Общая конфигурация PDFium для учебников.
//
// Школьные PDF часто используют внешние шрифты (включая математические).
// На Android их нужно явно предоставить PDFium, иначе часть формул и
// специальных символов может рендериться пустой.

import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

final hermesPdfFontManager = PdfFontManager(resolvers: const []);

Future<void> initializeHermesPdfEngine() async {
  await pdfrxFlutterInitialize();

  if (!Platform.isAndroid) {
    await hermesPdfFontManager.prepare();
    return;
  }

  const candidates = <String>[
    '/system/fonts',
    '/product/fonts',
    '/system/product/fonts',
    '/vendor/fonts',
    '/system/vendor/fonts',
  ];
  final fontPaths = candidates
      .where((path) => Directory(path).existsSync())
      .toList(growable: false);

  await hermesPdfFontManager.prepare(
    fontPaths: fontPaths.isEmpty ? null : fontPaths,
  );
}
