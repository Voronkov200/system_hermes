// Вырезка рамки (правило/теорема/формула/таблица) из официальной страницы
// учебника и прикладывание её к конспекту.
//
// Идея: раньше конспект показывал только текст, а оригинальная табличка/рамка
// оставалась на странице учебника отдельно. Здесь мы находим в PDF-тексте
// (у него есть координаты каждого символа) тот фрагмент, который соответствует
// правилу/термину, берём его ограничивающий прямоугольник и вырезаем его из
// уже отрендеренной страницы (2200px PNG).
//
// Это детерминированная эвристика без ИИ, целиком на телефоне. Она может
// резать неточно, поэтому:
//   * если текст правило не найден в PDF-слое — вырезка тихо пропускается;
//   * ориентация Y у pdfrx `PdfRect.bounds` неоднозначна (PDF — «Y вверх»,
//     а картинка — «Y вниз»), поэтому мы автоматически выбираем ориентацию
//     с наибольшим числом тёмных «чернил» — так в конспект всегда попадает
//     область с реальным текстом/рамкой, а не пустой белый угол страницы.

import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../agent/file_tools.dart';
import 'study_textbook_page_image_service.dart';
import 'study_textbook_service.dart';

/// Локальный alias, чтобы не писать `ui.Rect` в каждой сигнатуре.
typedef Rect = ui.Rect;

/// Запрос на вырезку таблички: учебник + страницы параграфа + текст правило.
typedef StudyTextbookCropRequest = ({
  String bookId,
  List<int> pdfPages,
  String text,
});

class StudyTextbookTableCropService {
  static const _cacheVersion = 1;
  static const _minTextLength = 12;
  static const _inkThreshold = 200; // luminance < 200 считается «чернилами»

  final StudyTextbookService _textbooks;
  final StudyTextbookPageImageService _pageImages;

  StudyTextbookTableCropService(this._textbooks, this._pageImages);

  /// Ищет правило/термин [ruleText] на странице [pdfPage] и возвращает
  /// вырезанную картинку, либо `null`, если локализовать не удалось.
  Future<File?> ensureTableCrop(String bookId, int pdfPage, String ruleText) async {
    final trimmed = ruleText.trim();
    if (trimmed.length < _minTextLength) return null;

    final root = await FileTools.root();
    final cacheDir = Directory(
      '${root.path}/study_page_crops/v$_cacheVersion/$bookId',
    );
    await cacheDir.create(recursive: true);

    final target = File(
      '${cacheDir.path}/page_$pdfPage-${trimmed.hashCode}.png',
    );
    if (await _isValidPng(target)) return target;
    if (await target.exists()) {
      try {
        await target.delete();
      } catch (_) {}
    }

    final pdf = await _textbooks.ensureLocal(bookId);
    final document = await pdfrx.PdfDocument.openFile(pdf.path);
    try {
      final actualPage = pdfPage.clamp(1, document.pages.length).toInt();
      final page = document.pages[actualPage - 1];
      final pageText = await page.loadStructuredText();
      final regex = _buildRegex(trimmed);
      final range = await _firstMatch(pageText, regex);
      if (range == null) return null;
      final bounds = range.bounds; // PdfRect, координаты страницы (top > bottom)

      final pageImage = await _pageImages.ensurePageImage(bookId, actualPage);
      final bytes = await pageImage.readAsBytes();
      final source = await _decodeImage(bytes);
      if (source == null) return null;

      try {
        final scaleX = source.width / page.width;
        final scaleY = source.height / page.height;
        final pad = page.width * scaleX * 0.045;

        // Два варианта ориентации Y (pdfrx отдаёт верх/низ неоднозначно).
        // Один из них обрезает пустой угол страницы, второй — реальную рамку.
        final flipRect = _expand(_rectFlipY(bounds, scaleX, scaleY, page.height), pad);
        final directRect = _expand(_rectDirect(bounds, scaleX, scaleY), pad);

        // Определяем, где больше «чернил» — туда и режем.
        final pixelData =
            await source.toByteData(format: ui.ImageByteFormat.rawRgba);
        final chosen = _pickInkRect(source, pixelData, flipRect, directRect);

        final cropped = await _cropImage(source, chosen);
        if (cropped == null) return null;
        final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
        cropped.dispose();
        if (png == null) return null;
        await target.writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          flush: true,
        );
      } finally {
        source.dispose();
      }

      if (!await _isValidPng(target)) {
        if (await target.exists()) await target.delete();
        return null;
      }
      return target;
    } finally {
      await document.dispose();
    }
  }

  // Ориентация «Y вверх» (PDF-координаты) -> переворачиваем в «Y вниз».
  Rect _rectFlipY(pdfrx.PdfRect b, double sx, double sy, double pageHeight) {
    return Rect.fromLTRB(
      b.left * sx,
      (pageHeight - b.top) * sy,
      b.right * sx,
      (pageHeight - b.bottom) * sy,
    );
  }

  // Ориентация «Y вниз» (положение уже совпадает с картинкой).
  Rect _rectDirect(pdfrx.PdfRect b, double sx, double sy) {
    return Rect.fromLTRB(
      b.left * sx,
      b.bottom * sy,
      b.right * sx,
      b.top * sy,
    );
  }

  Rect _expand(Rect r, double pad) => Rect.fromLTRB(
        r.left - pad,
        r.top - pad,
        r.right + pad,
        r.bottom + pad,
      );

  /// Выбирает прямоугольник с наибольшей долей тёмных пикселей.
  Rect _pickInkRect(
    ui.Image image,
    ByteData? pixelData,
    Rect flip,
    Rect direct,
  ) {
    if (pixelData == null) return flip;
    final a = _darkRatio(image, pixelData, flip);
    final b = _darkRatio(image, pixelData, direct);
    return b > a ? direct : flip;
  }

  double _darkRatio(ui.Image image, ByteData data, Rect rect) {
    final x0 = rect.left.floor().clamp(0, image.width - 1);
    final y0 = rect.top.floor().clamp(0, image.height - 1);
    final x1 = rect.right.ceil().clamp(x0 + 1, image.width);
    final y1 = rect.bottom.ceil().clamp(y0 + 1, image.height);
    if (x1 <= x0 || y1 <= y0) return 0;
    var dark = 0;
    var total = 0;
    for (var y = y0; y < y1; y += 2) {
      for (var x = x0; x < x1; x += 2) {
        final i = (y * image.width + x) * 4;
        final r = data.getUint8(i);
        final g = data.getUint8(i + 1);
        final b = data.getUint8(i + 2);
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        if (lum < _inkThreshold) dark++;
        total++;
      }
    }
    return total == 0 ? 0 : dark / total;
  }

  RegExp _buildRegex(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    return RegExp(
      words.map(RegExp.escape).join(r'\s+'),
      caseSensitive: false,
    );
  }

  Future<pdfrx.PdfPageTextRange?> _firstMatch(
    pdfrx.PdfPageText pageText,
    RegExp regex,
  ) async {
    await for (final match in pageText.allMatches(regex)) {
      return match;
    }
    return null;
  }

  Future<ui.Image?> _decodeImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image?> _cropImage(ui.Image src, Rect srcRect) async {
    final width = src.width.toDouble();
    final height = src.height.toDouble();
    final rect = Rect.fromLTRB(
      srcRect.left.clamp(0.0, width),
      srcRect.top.clamp(0.0, height),
      srcRect.right.clamp(0.0, width),
      srcRect.bottom.clamp(0.0, height),
    );
    if (rect.width < 14 || rect.height < 14) return null;
    if (!rect.left.isFinite ||
        !rect.top.isFinite ||
        !rect.right.isFinite ||
        !rect.bottom.isFinite) {
      return null;
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      src,
      rect,
      Rect.fromLTWH(0, 0, rect.width, rect.height),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    return picture.toImage(
      rect.width.round().clamp(1, 4096),
      rect.height.round().clamp(1, 4096),
    );
  }

  Future<bool> _isValidPng(File file) async {
    if (!await file.exists() || await file.length() < 400) return false;
    final header = await file.openRead(0, 8).fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    return header.length >= 8 &&
        header[0] == 0x89 &&
        header[1] == 0x50 &&
        header[2] == 0x4E &&
        header[3] == 0x47 &&
        header[4] == 0x0D &&
        header[5] == 0x0A &&
        header[6] == 0x1A &&
        header[7] == 0x0A;
  }
}

final studyTextbookTableCropServiceProvider =
    Provider<StudyTextbookTableCropService>((ref) {
  return StudyTextbookTableCropService(
    ref.read(studyTextbookServiceProvider),
    ref.read(studyTextbookPageImageServiceProvider),
  );
});

final studyTextbookCropProvider = FutureProvider.autoDispose
    .family<File?, StudyTextbookCropRequest>((ref, request) {
  final service = ref.read(studyTextbookTableCropServiceProvider);
  return _resolveCrop(service, request);
});

Future<File?> _resolveCrop(
  StudyTextbookTableCropService service,
  StudyTextbookCropRequest request,
) async {
  for (final page in request.pdfPages) {
    final file = await service.ensureTableCrop(request.bookId, page, request.text);
    if (file != null) return file;
  }
  return null;
}
