// Файловые инструменты агента: создание/чтение файлов и PDF-документация.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

class FileTools {
  static Future<Directory> root() async {
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

  /// Resolve a relative path inside Hermes root. Reject traversal instead of
  /// silently rewriting it; security decisions must fail closed.
  static String _join(String root, String path) {
    final clean = path.replaceAll('\\', '/').trim();
    if (clean.isEmpty) return root;
    if (clean.startsWith('/') || clean.contains('..')) {
      throw ArgumentError('Недопустимый путь: $path');
    }
    final parts = clean.split('/').where((p) => p.isNotEmpty && p != '.');
    return '$root/${parts.join('/')}';
  }

  static Future<String> writeFile(String path, String content) async {
    final rootDir = await root();
    final full = File(_join(rootDir.path, path));
    await full.parent.create(recursive: true);
    await full.writeAsString(content);
    return 'Создан файл: ${full.path}\nРазмер: ${content.length} символов.';
  }

  static Future<String> readFile(String path) async {
    final rootDir = await root();
    final full = File(_join(rootDir.path, path));
    if (!full.existsSync()) return 'Файл не найден: $path';
    var text = await full.readAsString();
    if (text.length > 8000) text = '${text.substring(0, 8000)}…';
    return 'Содержимое $path:\n$text';
  }

  static Future<String> listDir(String path) async {
    final rootDir = await root();
    final dir = Directory(_join(rootDir.path, path));
    if (!dir.existsSync()) return 'Папка не найдена: $path';
    final entries = await dir.list().toList();
    if (entries.isEmpty) return 'Папка пуста: $path';
    final parts = entries
        .map((e) => e is Directory
            ? '📁 ${e.uri.pathSegments.last}/'
            : '📄 ${e.uri.pathSegments.last} (${(e as File).lengthSync()} б)')
        .toList()
      ..sort();
    return 'Содержимое $path:\n${parts.take(100).join('\n')}';
  }

  static Future<String> readPdf(String path, {String pages = ''}) async {
    final rootDir = await root();
    final full = File(_join(rootDir.path, path));
    if (!full.existsSync()) return 'Файл не найден: $path';

    final doc = await pdfrx.PdfDocument.openFile(full.path);
    final total = doc.pages.length;
    var start = 1;
    var end = total;
    if (pages.trim().isNotEmpty) {
      final m = RegExp(r'^(\d+)(?:\s*[-–]\s*(\d+))?$').firstMatch(pages.trim());
      if (m != null) {
        start = int.parse(m.group(1)!);
        end = m.group(2) != null ? int.parse(m.group(2)!) : start;
        if (start < 1) start = 1;
        if (end > total) end = total;
        if (start > end) {
          await doc.dispose();
          return 'Неверный диапазон страниц (всего $total).';
        }
      }
    }

    final buffer = StringBuffer();
    var chars = 0;
    const maxChars = 20000;
    try {
      for (var i = start; i <= end && chars < maxChars; i++) {
        try {
          final text = await doc.pages[i - 1].loadStructuredText();
          final content = text.fullText.trim();
          if (content.isEmpty) continue;
          buffer.writeln('--- стр. $i ---');
          buffer.writeln(content);
          chars += content.length;
        } catch (_) {}
      }
    } finally {
      await doc.dispose();
    }

    var out = buffer.toString().trim();
    if (out.isEmpty) {
      return 'Текст из PDF не извлекается (возможно, это скан без OCR). В PDF $total страниц.';
    }
    final pagesDone = chars >= maxChars
        ? 'первые страницы (лимит $maxChars символов)'
        : 'страницы $start-$end';
    if (chars >= maxChars) out = '${out.substring(0, maxChars)}…';
    return 'PDF: $path ($total стр.), извлечено: $pagesDone.\n$out';
  }

  static Future<String> makePdf({
    required String title,
    required String text,
    String outPath = '',
  }) async {
    final rootDir = await root();
    final fileName = outPath.isNotEmpty ? outPath : 'docs/${_safeName(title)}.pdf';
    final full = File(_join(rootDir.path, fileName));
    await full.parent.create(recursive: true);
    final fontData = await _systemCyrillicFont();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: fontData != null
              ? pw.Font.ttf(ByteData.sublistView(fontData))
              : pw.Font.helvetica(),
        ),
        build: (ctx) => [
          pw.Header(level: 0, child: pw.Text(title, style: const pw.TextStyle(fontSize: 20))),
          pw.SizedBox(height: 12),
          for (final line in text.split('\n'))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(line, textAlign: pw.TextAlign.left),
            ),
        ],
      ),
    );
    await full.writeAsBytes(await doc.save());
    return 'PDF создан: ${full.path}';
  }

  static Future<Uint8List?> _systemCyrillicFont() async {
    const candidates = [
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      '/system/fonts/NotoSansCJK-Regular.ttc',
      '/system/fonts/DroidSansFallback.ttf',
    ];
    for (final path in candidates) {
      try {
        final f = File(path);
        if (await f.exists()) return f.readAsBytes();
      } catch (_) {}
    }
    return null;
  }

  static String _safeName(String s) {
    final clean = s.replaceAll(RegExp(r'[^\wа-яА-ЯёЁ\- ]'), '').trim();
    return clean.isEmpty ? 'document' : clean.replaceAll(' ', '_');
  }
}
