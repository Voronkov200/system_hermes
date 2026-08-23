// Рендер официальных страниц учебника в локальные PNG.
//
// PDF остаётся первоисточником, но пользовательский экран после первого
// рендера показывает стабильное изображение страницы. Это убирает зависимость
// интерфейса от повторного live-рендера PDF и сохраняет формулы/рисунки ровно
// в том виде, в котором их отдал PDFium с настроенными fallback-шрифтами.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../agent/file_tools.dart';
import 'study_pdf_service.dart';
import 'study_textbook_service.dart';

typedef StudyTextbookPageImageRequest = ({String bookId, int pdfPage});

class StudyTextbookPageImageException implements Exception {
  final String message;

  const StudyTextbookPageImageException(this.message);

  @override
  String toString() => message;
}

class StudyTextbookPageImageService {
  // При изменении параметров рендера достаточно увеличить версию: старые PNG
  // автоматически перестанут использоваться без удаления PDF пользователя.
  static const _cacheVersion = 2;
  static const _targetWidth = 2200;

  final StudyTextbookService _textbooks;
  final Map<String, Future<File>> _inFlight = <String, Future<File>>{};

  StudyTextbookPageImageService(this._textbooks);

  Future<File> ensurePageImage(String bookId, int pdfPage) {
    final safePage = pdfPage < 1 ? 1 : pdfPage;
    final key = '$bookId:$safePage:v$_cacheVersion';
    final active = _inFlight[key];
    if (active != null) return active;

    late final Future<File> tracked;
    tracked = _ensurePageImage(bookId, safePage).whenComplete(() {
      if (identical(_inFlight[key], tracked)) {
        _inFlight.remove(key);
      }
    });
    _inFlight[key] = tracked;
    return tracked;
  }

  Future<File> _ensurePageImage(String bookId, int pdfPage) async {
    final root = await FileTools.root();
    final directory = Directory(
      '${root.path}/study_page_images/v$_cacheVersion/$bookId',
    );
    await directory.create(recursive: true);

    final target = File('${directory.path}/page_$pdfPage.png');
    if (await _isValidPng(target)) return target;
    if (await target.exists()) {
      try {
        await target.delete();
      } catch (_) {}
    }

    final pdf = await _textbooks.ensureLocal(bookId);
    final document = await pdfrx.PdfDocument.openFile(pdf.path);
    try {
      if (document.pages.isEmpty) {
        throw const StudyTextbookPageImageException(
          'В учебнике не найдено страниц.',
        );
      }

      associateHermesPdfFonts(document);
      final actualPage = pdfPage.clamp(1, document.pages.length).toInt();
      final page = document.pages[actualPage - 1];
      final scale = _targetWidth / page.width;
      final width = _targetWidth;
      final height = (page.height * scale).round().clamp(1, 4000);

      final rendered = await page.render(
        width: width,
        height: height,
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) {
        throw const StudyTextbookPageImageException(
          'PDF-страница не отрисовалась.',
        );
      }

      try {
        final image = await rendered.createImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null || bytes.lengthInBytes < 1024) {
            throw const StudyTextbookPageImageException(
              'Не удалось получить изображение страницы.',
            );
          }
          await target.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            flush: true,
          );
        } finally {
          image.dispose();
        }
      } finally {
        rendered.dispose();
      }

      if (!await _isValidPng(target)) {
        if (await target.exists()) await target.delete();
        throw const StudyTextbookPageImageException(
          'Кэш страницы повреждён. Повтори открытие параграфа.',
        );
      }
      return target;
    } finally {
      await document.dispose();
    }
  }

  Future<bool> _isValidPng(File file) async {
    try {
      if (!await file.exists() || await file.length() < 1024) return false;
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
    } catch (_) {
      return false;
    }
  }
}

final studyTextbookPageImageServiceProvider =
    Provider<StudyTextbookPageImageService>((ref) {
  return StudyTextbookPageImageService(
    ref.read(studyTextbookServiceProvider),
  );
});

final studyTextbookPageImageProvider = FutureProvider.autoDispose
    .family<File, StudyTextbookPageImageRequest>((ref, request) {
  return ref.read(studyTextbookPageImageServiceProvider).ensurePageImage(
        request.bookId,
        request.pdfPage,
      );
});
