// Модуль «Документы» (в стиле NotebookLM): источники знаний.
//
// Источники: PDF-учебники, заметки Obsidian, вставленный текст,
// транскрибации лекций. Поверх источников — конспекты по параграфам
// и ответы на вопросы строго по документам (Groq).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../core/constants.dart';
import '../../data/models.dart';
import 'llm.dart';

@HiveType(typeId: 14)
class SourceDoc {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  /// Тип: pdf | obsidian | text | transcribe
  @HiveField(2)
  final String sourceType;
  /// Текст источника (для obsidian — пусто, читается из файла).
  @HiveField(3)
  final String content;
  /// Путь к файлу (PDF) или заметке Obsidian.
  @HiveField(4)
  final String? filePath;
  @HiveField(5)
  final DateTime addedAt;

  const SourceDoc({
    required this.id,
    required this.title,
    required this.sourceType,
    this.content = '',
    this.filePath,
    required this.addedAt,
  });
}

class SourceDocAdapter extends TypeAdapter<SourceDoc> {
  @override
  final int typeId = 14;

  @override
  SourceDoc read(BinaryReader reader) => SourceDoc(
        id: reader.readString(),
        title: reader.readString(),
        sourceType: reader.readString(),
        content: reader.readString(),
        filePath: reader.readBool()
            ? reader.readString()
            : null,
        addedAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      );

  @override
  void write(BinaryWriter writer, SourceDoc obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.title)
      ..writeString(obj.sourceType)
      ..writeString(obj.content)
      ..writeBool(obj.filePath != null);
    if (obj.filePath != null) writer.writeString(obj.filePath!);
    writer.writeInt(obj.addedAt.millisecondsSinceEpoch);
  }
}

class SourcesState {
  final List<SourceDoc> docs;
  final bool busy;
  final String? error;

  const SourcesState({
    this.docs = const [],
    this.busy = false,
    this.error,
  });

  SourcesState copyWith({
    List<SourceDoc>? docs,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return SourcesState(
      docs: docs ?? this.docs,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Контроллер источников документов.
class SourcesController extends Notifier<SourcesState> {
  late final Box<SourceDoc> _box;

  @override
  SourcesState build() {
    _box = Hive.box<SourceDoc>(BoxNames.docs);
    return SourcesState(docs: _sorted());
  }

  List<SourceDoc> _sorted() {
    final list = _box.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  void _emit() => state = state.copyWith(docs: _sorted());

  /// Полный текст источника (для Obsidian читается с диска).
  Future<String> loadContent(SourceDoc doc) async {
    if (doc.sourceType == 'obsidian' && doc.filePath != null) {
      try {
        return await File(doc.filePath!).readAsString();
      } catch (_) {
        return '';
      }
    }
    return doc.content;
  }

  Future<void> add({
    required String title,
    required String sourceType,
    String content = '',
    String? filePath,
  }) async {
    final id = genId();
    await _box.put(
      id,
      SourceDoc(
        id: id,
        title: title.trim().isEmpty ? 'Без названия' : title.trim(),
        sourceType: sourceType,
        content: content,
        filePath: filePath,
        addedAt: DateTime.now(),
      ),
    );
    _emit();
  }

  Future<void> remove(String id) async {
    await _box.delete(id);
    _emit();
  }

  /// Извлечение текста из PDF (учебники), лимит 60 000 символов.
  Future<String> extractPdfText(String path, {int maxChars = 60000}) async {
    final doc = await pdfrx.PdfDocument.openFile(path);
    final buffer = StringBuffer();
    var chars = 0;
    try {
      for (var i = 0; i < doc.pages.length && chars < maxChars; i++) {
        try {
          final page = doc.pages[i];
          final text = await page.loadStructuredText();
          final content = text.fullText.trim();
          if (content.isEmpty) continue;
          buffer.writeln('--- стр. ${i + 1} ---');
          buffer.writeln(content);
          chars += content.length;
        } catch (_) {}
      }
    } finally {
      await doc.dispose();
    }
    var out = buffer.toString().trim();
    if (out.isEmpty) {
      throw Exception('Текст из PDF не извлекается: вероятно, это скан без '
          'OCR-слоя.');
    }
    if (out.length > maxChars) {
      out = '${out.substring(0, maxChars)}…';
    }
    return out;
  }

  /// Конспект источника по разделам (параграфам). Прогресс через onProgress.
  Future<String> makeConspectus(
    WidgetRef ref,
    SourceDoc doc, {
    void Function(int done, int total)? onProgress,
  }) async {
    final content = await loadContent(doc);
    if (content.trim().isEmpty) {
      throw Exception('Источник пуст — нечего конспектировать.');
    }
    final sections = splitSections(content);
    final parts = <String>[];
    for (var i = 0; i < sections.length; i++) {
      onProgress?.call(i + 1, sections.length);
      final summary = await llmComplete(
        ref.container,
        system: 'Ты — ассистент для конспектирования учебных материалов. '
            'Составь сжатый конспект приведённого фрагмента: главные мысли '
            'тезисами, определения, формулы, даты, имена. Пиши по-русски, '
            'используй markdown-списки. Ничего не придумывай сверх текста.',
        user: sections[i],
        maxTokens: 800,
        timeoutSeconds: 90,
      );
      parts.add('## Раздел ${i + 1}\n\n$summary');
    }
    return '# Конспект: ${doc.title}\n\n'
        'Источник: ${doc.title}\n\n${parts.join('\n\n')}';
  }

  /// Вопрос по документам (NotebookLM-стиль): ответ только по фрагментам.
  Future<DocAnswer> askDocuments(
    WidgetRef ref,
    List<SourceDoc> docs,
    String question,
  ) async {
    final chunks = <({String source, String text})>[];
    for (final doc in docs) {
      final content = await loadContent(doc);
      if (content.trim().isEmpty) continue;
      for (final c in chunkText(content)) {
        chunks.add((source: doc.title, text: c));
      }
    }
    if (chunks.isEmpty) {
      throw Exception('Нет источников с текстом — добавь документы.');
    }

    final words = question
        .toLowerCase()
        .replaceAll(RegExp(r'[^\wа-яё\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();

    final scored = <({String source, String text, int score})>[];
    for (final c in chunks) {
      var score = 0;
      final lower = c.text.toLowerCase();
      for (final w in words) {
        score += RegExp(RegExp.escape(w), caseSensitive: false)
            .allMatches(lower)
            .length;
      }
      if (score > 0) {
        scored.add((source: c.source, text: c.text, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.take(5).toList();
    if (top.isEmpty) {
      throw Exception('По документам не нашлось ничего по вопросу — '
          'попробуй сформулировать иначе.');
    }

    final fragments = top.asMap().entries.map((e) {
      final i = e.key + 1;
      return '[$i] Источник: ${e.value.source}\n${e.value.text}';
    }).join('\n\n---\n\n');

    final answer = await llmComplete(
      ref.container,
      system: 'Ты — ассистент по работе с документами в стиле NotebookLM. '
          'Отвечай на вопрос ПО-РУССКИ, используя ТОЛЬКО приведённые '
          'фрагменты документов. Кратко и по делу. Указывай фрагменты так: '
          '[1], [2]. Если в фрагментах нет ответа — напиши «В документах '
          'этого нет», не выдумывай.',
      user: 'Вопрос: $question\n\nФрагменты документов:\n$fragments',
      maxTokens: 1000,
      timeoutSeconds: 120,
    );

    return DocAnswer(text: answer, sources: top.map((t) => t.source).toList());
  }
}

/// Ответ по документам.
class DocAnswer {
  final String text;
  final List<String> sources;

  const DocAnswer({required this.text, required this.sources});
}

final docsProvider =
    NotifierProvider<SourcesController, SourcesState>(SourcesController.new);

/// Разбиение текста на разделы: сначала по заголовкам параграфов/глав,
/// если заголовков нет — по блокам максимальной длины.
List<String> splitSections(String text, {int maxLen = 8000}) {
  final lines = text.split('\n');
  final sections = <String>[];
  var current = StringBuffer();

  void flush() {
    final s = current.toString().trim();
    if (s.isNotEmpty) sections.add(s);
    current = StringBuffer();
  }

  final headingRe = RegExp(
      r'^\s*(§\s*\d+|Параграф\s+\d+|Глава\s+\d+|Тема\s+\d+|Урок\s+\d+|'
      r'\d{1,3}[.][\s\S]|Практическая\s+работа|Лабораторная\s+работа)',
      caseSensitive: false);

  var headingCount = 0;
  for (final line in lines) {
    if (headingRe.hasMatch(line)) {
      headingCount++;
      if (headingCount > 1) flush();
    }
    if (current.length + line.length > maxLen) flush();
    current.writeln(line);
  }
  flush();

  if (headingCount > 1) return sections;
  // Заголовков нет — режим «документация»: по блокам.
  return chunkText(text, size: maxLen);
}

/// Разбиение текста на перекрывающиеся фрагменты для поиска.
List<String> chunkText(String text, {int size = 1600, int overlap = 120}) {
  final clean = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (clean.length <= size) {
    return clean.isEmpty ? const [] : [clean];
  }
  final chunks = <String>[];
  var start = 0;
  while (start < clean.length) {
    var end = start + size;
    if (end < clean.length) {
      // режем по границе абзаца, если она близко
      final cut = clean.lastIndexOf('\n\n', end);
      if (cut > start + size ~/ 2) end = cut;
    } else {
      end = clean.length;
    }
    chunks.add(clean.substring(start, end).trim());
    if (end >= clean.length) break;
    start = end - overlap;
    if (start < 0) start = 0;
  }
  return chunks.where((c) => c.isNotEmpty).toList();
}
