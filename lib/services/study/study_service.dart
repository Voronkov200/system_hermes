// Модуль «Учёба»: предметы 11 класса по белорусской школьной программе.
//
// Предмет (StudySubject) — из каталога [studyCatalog] либо добавленный
// вручную (в т.ч. дополнительная литература/пособия). К предмету
// прикрепляется PDF-учебник; его текст извлекается, режется на параграфы
// (StudyParagraph), каждый параграф разбирается LLM: конспект, план,
// правила/теоремы со страницами, решения заданий, ответы на вопросы,
// краткое содержание произведений.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../data/study_catalog.dart';
import '../agent/file_tools.dart';
import '../settings_service.dart';
import '../plan/docs_service.dart' show splitSections;
import '../plan/llm.dart';

/// Предмет (или дополнительная литература) в «Учёбе».
@HiveType(typeId: 12)
class StudySubject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  /// Ключ иконки: history | world | lang_ru | lit_ru | algebra | ...
  @HiveField(2)
  final String icon;
  /// subject — школьный предмет, guide — доп. литература/пособие.
  @HiveField(3)
  final String kind;
  @HiveField(4)
  final String category;
  @HiveField(5)
  final String subtitle;
  /// Тип разбора LLM: humanities | exact | languages | literature.
  @HiveField(6)
  final String analysis;
  /// Путь к прикреплённому PDF-учебнику.
  @HiveField(7)
  final String? filePath;
  @HiveField(8)
  final DateTime addedAt;

  const StudySubject({
    required this.id,
    required this.title,
    this.icon = 'book',
    this.kind = 'subject',
    this.category = '',
    this.subtitle = '',
    this.analysis = 'humanities',
    this.filePath,
    required this.addedAt,
  });

  StudySubject copyWith({
    String? title,
    String? icon,
    String? kind,
    String? category,
    String? subtitle,
    String? analysis,
    String? filePath,
  }) =>
      StudySubject(
        id: id,
        title: title ?? this.title,
        icon: icon ?? this.icon,
        kind: kind ?? this.kind,
        category: category ?? this.category,
        subtitle: subtitle ?? this.subtitle,
        analysis: analysis ?? this.analysis,
        filePath: filePath ?? this.filePath,
        addedAt: addedAt,
      );
}

class StudySubjectAdapter extends TypeAdapter<StudySubject> {
  @override
  final int typeId = 12;

  @override
  StudySubject read(BinaryReader reader) => StudySubject(
        id: reader.readString(),
        title: reader.readString(),
        icon: reader.readString(),
        kind: reader.readString(),
        category: reader.readString(),
        subtitle: reader.readString(),
        analysis: reader.readString(),
        filePath: reader.readBool() ? reader.readString() : null,
        addedAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      );

  @override
  void write(BinaryWriter writer, StudySubject obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.title)
      ..writeString(obj.icon)
      ..writeString(obj.kind)
      ..writeString(obj.category)
      ..writeString(obj.subtitle)
      ..writeString(obj.analysis)
      ..writeBool(obj.filePath != null);
    if (obj.filePath != null) writer.writeString(obj.filePath!);
    writer.writeInt(obj.addedAt.millisecondsSinceEpoch);
  }
}

/// Параграф (раздел/произведение) предмета.
@HiveType(typeId: 13)
class StudyParagraph {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String subjectId;
  @HiveField(2)
  final String title;
  /// Название главы/раздела, если есть.
  @HiveField(3)
  final String chapter;
  /// Страницы учебника, например «с. 34–38».
  @HiveField(4)
  final String pages;
  /// Сырой текст параграфа из PDF (источник для LLM).
  @HiveField(5)
  final String sourceText;
  /// Сгенерированный конспект (markdown).
  @HiveField(6)
  final String content;
  /// Прочитано/выучено (галочка пользователя).
  @HiveField(7)
  final bool learned;
  @HiveField(8)
  final DateTime updatedAt;

  const StudyParagraph({
    required this.id,
    required this.subjectId,
    required this.title,
    this.chapter = '',
    this.pages = '',
    this.sourceText = '',
    this.content = '',
    this.learned = false,
    required this.updatedAt,
  });

  StudyParagraph copyWith({
    String? title,
    String? chapter,
    String? pages,
    String? sourceText,
    String? content,
    bool? learned,
    DateTime? updatedAt,
  }) =>
      StudyParagraph(
        id: id,
        subjectId: subjectId,
        title: title ?? this.title,
        chapter: chapter ?? this.chapter,
        pages: pages ?? this.pages,
        sourceText: sourceText ?? this.sourceText,
        content: content ?? this.content,
        learned: learned ?? this.learned,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class StudyParagraphAdapter extends TypeAdapter<StudyParagraph> {
  @override
  final int typeId = 13;

  @override
  StudyParagraph read(BinaryReader reader) => StudyParagraph(
        id: reader.readString(),
        subjectId: reader.readString(),
        title: reader.readString(),
        chapter: reader.readString(),
        pages: reader.readString(),
        sourceText: reader.readString(),
        content: reader.readString(),
        learned: reader.readBool(),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      );

  @override
  void write(BinaryWriter writer, StudyParagraph obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.subjectId)
      ..writeString(obj.title)
      ..writeString(obj.chapter)
      ..writeString(obj.pages)
      ..writeString(obj.sourceText)
      ..writeString(obj.content)
      ..writeBool(obj.learned)
      ..writeInt(obj.updatedAt.millisecondsSinceEpoch);
  }
}

/// Состояние модуля «Учёба».
class StudyState {
  final List<StudySubject> subjects;
  final List<StudyParagraph> paragraphs;
  final bool busy;
  final String? error;
  /// id параграфа, который сейчас разбирает LLM.
  final String? workingId;

  const StudyState({
    this.subjects = const [],
    this.paragraphs = const [],
    this.busy = false,
    this.error,
    this.workingId,
  });

  StudyState copyWith({
    List<StudySubject>? subjects,
    List<StudyParagraph>? paragraphs,
    bool? busy,
    String? error,
    bool clearError = false,
    String? workingId,
    bool clearWorking = false,
  }) =>
      StudyState(
        subjects: subjects ?? this.subjects,
        paragraphs: paragraphs ?? this.paragraphs,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        workingId: clearWorking ? null : (workingId ?? this.workingId),
      );
}

/// Контроллер «Учёбы»: каталог, параграфы, LLM-разбор.
class StudyController extends Notifier<StudyState> {
  late final Box<StudySubject> _box;
  late final Box<StudyParagraph> _pbox;

  @override
  StudyState build() {
    _box = Hive.box<StudySubject>(BoxNames.study);
    _pbox = Hive.box<StudyParagraph>(BoxNames.studyParagraphs);
    _ensureCatalog();
    return StudyState(
      subjects: _sortedSubjects(),
      paragraphs: _pbox.values.toList(),
    );
  }

  void _ensureCatalog() {
    if (_box.isNotEmpty) return;
    for (final item in studyCatalog) {
      final id = genId();
      _box.put(
        id,
        StudySubject(
          id: id,
          title: item.title,
          icon: item.icon,
          kind: item.kind,
          category: item.category,
          subtitle: item.subtitle,
          analysis: _analysisFor(item.title),
          addedAt: DateTime.now(),
        ),
      );
    }
  }

  static String _analysisFor(String title) {
    const lit = ['литератур', 'літаратур'];
    if (lit.any(title.toLowerCase().contains)) return 'literature';
    const exact = [
      'алгебра', 'геометрия', 'физика', 'химия', 'биология',
      'информатика', 'астрономия', 'математика',
    ];
    if (exact.any(title.toLowerCase().contains)) return 'exact';
    const langs = ['язык', 'мова', 'английский', 'белорусский', 'русский'];
    if (langs.any(title.toLowerCase().contains)) return 'languages';
    return 'humanities';
  }

  List<StudySubject> _sortedSubjects() {
    final list = _box.values.toList();
    const order = ['subject', 'guide'];
    list.sort((a, b) {
      final k = order.indexOf(a.kind).compareTo(order.indexOf(b.kind));
      if (k != 0) return k;
      return a.title.compareTo(b.title);
    });
    return list;
  }

  void _emit() {
    state = state.copyWith(
      subjects: _sortedSubjects(),
      paragraphs: _pbox.values.toList(),
    );
  }

  StudySubject? subjectOf(String id) {
    for (final s in _box.values) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<StudyParagraph> paragraphsOf(String subjectId) {
    final list = _pbox.values
        .where((p) => p.subjectId == subjectId)
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  // ------------------------------------------------------------------
  // Предметы
  // ------------------------------------------------------------------

  /// Добавление предмета или доп. литературы вручную.
  Future<StudySubject> addSubject({
    required String title,
    String icon = 'book',
    String kind = 'subject',
    String category = '',
    String subtitle = '',
  }) async {
    final s = StudySubject(
      id: genId(),
      title: title.trim().isEmpty ? 'Без названия' : title.trim(),
      icon: icon,
      kind: kind,
      category: category,
      subtitle: subtitle,
      analysis: _analysisFor(title),
      addedAt: DateTime.now(),
    );
    await _box.put(s.id, s);
    _emit();
    return s;
  }

  Future<void> updateSubject(StudySubject s) async {
    await _box.put(s.id, s);
    _emit();
  }

  Future<void> removeSubject(String id) async {
    await _box.delete(id);
    for (final p in _pbox.values.where((p) => p.subjectId == id)) {
      await _pbox.delete(p.id);
    }
    _emit();
  }

  /// Прикрепление PDF-учебника: файл копируется в каталог Hermes.
  Future<String> attachPdf(StudySubject subject, String srcPath) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final rootDir = await FileTools.root();
      final targetDir = Directory('${rootDir.path}/study');
      await targetDir.create(recursive: true);
      final ext = srcPath.split('.').last.toLowerCase();
      final target =
          '${targetDir.path}/${subject.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(srcPath).copy(target);
      final s = subject.copyWith(filePath: target);
      await _box.put(s.id, s);
      state = state.copyWith(busy: false);
      _emit();
      return target;
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
      rethrow;
    }
  }

  // ------------------------------------------------------------------
  // Параграфы
  // ------------------------------------------------------------------

  Future<StudyParagraph> addParagraph(
    StudySubject subject, {
    required String title,
    String chapter = '',
    String pages = '',
    String sourceText = '',
  }) async {
    final p = StudyParagraph(
      id: genId(),
      subjectId: subject.id,
      title: title.trim().isEmpty ? 'Без названия' : title.trim(),
      chapter: chapter,
      pages: pages,
      sourceText: sourceText,
      updatedAt: DateTime.now(),
    );
    await _pbox.put(p.id, p);
    _emit();
    return p;
  }

  Future<void> updateParagraph(StudyParagraph p) async {
    await _pbox.put(p.id, p);
    _emit();
  }

  Future<void> toggleLearned(String id) async {
    final p = _pbox.get(id);
    if (p == null) return;
    await _pbox.put(id, p.copyWith(learned: !p.learned, updatedAt: DateTime.now()));
    _emit();
  }

  Future<void> removeParagraph(String id) async {
    await _pbox.delete(id);
    _emit();
  }

  // ------------------------------------------------------------------
  // Разбор PDF на параграфы
  // ------------------------------------------------------------------

  /// Извлечение текста PDF (страницы помечаются «--- стр. N ---»).
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
    if (out.length > maxChars) out = out.substring(0, maxChars);
    return out;
  }

  /// Нарезка извлечённого текста на параграфы. Возвращает список
  /// (заголовок, глава, страницы, текст).
  List<({String title, String chapter, String pages, String text})> splitPdfToParagraphs(
    String pdfText,
  ) {
    final sections = splitSections(pdfText);
    final result = <({String title, String chapter, String pages, String text})>[];
    final pageRe = RegExp(r'---\s*стр\.\s*(\d+)\s*---');

    for (final section in sections) {
      final lines = section.split('\n');
      String? heading;
      var start = 0;
      for (var i = 0; i < lines.length; i++) {
        final t = lines[i].replaceAll(pageRe, '').trim();
        if (t.isNotEmpty) {
          heading = t;
          start = i;
          break;
        }
      }
      // Глава/раздел или сам параграф.
      final title = heading ?? 'Параграф';
      String chapter = '';
      if (title.isNotEmpty) {
        final chRe = RegExp(
            r'^(Глава\s+\d+|Раздел\s+\d+|Часть\s+\d+)[.:]?\s*(.*)$',
            caseSensitive: false);
        final m = chRe.firstMatch(title);
        if (m != null) {
          chapter = m.group(1)!;
          final rest = m.group(2)?.trim() ?? '';
          if (rest.isNotEmpty) heading = rest;
        }
      }
      // Номера страниц из маркеров внутри секции.
      final pages = pageRe.allMatches(section).map((m) => m.group(1)).join(', ');
      final text = lines.skip(start).join('\n').replaceAll(pageRe, '').trim();
      if (text.isEmpty) continue;
      result.add((
        title: heading ?? title,
        chapter: chapter,
        pages: pages.isEmpty ? '' : 'с. $pages',
        text: text,
      ));
    }
    return result;
  }

  /// Разбор PDF на параграфы и создание StudyParagraph (без LLM —
  /// только нарезка; конспект генерируется отдельно по каждому).
  Future<void> parsePdf(StudySubject subject) async {
    if (subject.filePath == null) {
      throw Exception('К предмету не прикреплён PDF-учебник.');
    }
    state = state.copyWith(busy: true, error: null);
    try {
      final text = await extractPdfText(subject.filePath!);
      final parts = splitPdfToParagraphs(text);
      if (parts.isEmpty) {
        throw Exception('В учебнике не нашлось параграфов — возможно, '
            'не текстовый PDF.');
      }
      for (final part in parts) {
        await _pbox.put(
          genId(),
          StudyParagraph(
            id: genId(),
            subjectId: subject.id,
            title: part.title,
            chapter: part.chapter,
            pages: part.pages,
            sourceText: part.text,
            updatedAt: DateTime.now(),
          ),
        );
      }
      state = state.copyWith(busy: false);
      _emit();
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
      rethrow;
    }
  }

  /// Полная пере-нарезка: старые параграфы удаляются.
  Future<void> reparsePdf(StudySubject subject) async {
    for (final p in _pbox.values.where((p) => p.subjectId == subject.id)) {
      await _pbox.delete(p.id);
    }
    await parsePdf(subject);
  }

  // ------------------------------------------------------------------
  // LLM-разбор параграфа
  // ------------------------------------------------------------------

  /// Режимы разбора параграфа.
  static const modeConspectus = 'conspectus'; // конспект + план
  static const modeRules = 'rules'; // правила/теоремы/формулы
  static const modeTasks = 'tasks'; // разбор заданий по пунктам
  static const modeAnswers = 'answers'; // ответы на вопросы после параграфа
  static const modeSummary = 'summary'; // краткое содержание (литература)

  /// Генерация конспекта/разбора параграфа через LLM.
  /// [mode] — StudyController.mode*.
  Future<String> analyzeParagraph(
    StudyParagraph p, {
    String mode = modeConspectus,
  }) async {
    final subject = subjectOf(p.subjectId);
    if (subject == null) throw Exception('Предмет не найден.');
    final s = ref.read(settingsProvider);
    final source = p.sourceText.trim().isEmpty
        ? p.content.trim().isEmpty
            ? 'Параграф: ${p.title}'
            : p.content
        : p.sourceText;

    final sys = _systemPrompt(subject, mode);
    final user = 'Учебник: ${subject.title}'
        '${subject.subtitle.isEmpty ? '' : ' (${subject.subtitle})'}\n'
        'Глава: ${p.chapter.isEmpty ? '—' : p.chapter}\n'
        'Параграф: ${p.title}'
        '${p.pages.isEmpty ? '' : ' · ${p.pages}'}\n\n'
        'Текст параграфа:\n$source';

    state = state.copyWith(busy: true, error: null, workingId: p.id);
    try {
      final answer = await llmComplete(
        s,
        system: sys,
        user: user,
        maxTokens: 3000,
        timeoutSeconds: 180,
        temperature: 0.3,
      );
      final updated = p.copyWith(
        content: answer,
        updatedAt: DateTime.now(),
      );
      await _pbox.put(p.id, updated);
      state = state.copyWith(
        busy: false,
        clearError: true,
        clearWorking: true,
      );
      return answer;
    } catch (e) {
      state = state.copyWith(
        busy: false,
        error: '$e',
        clearWorking: true,
      );
      rethrow;
    }
  }

  String _systemPrompt(StudySubject subject, String mode) {
    final base = 'Ты — репетитор по предмету «${subject.title}» '
        'за 11 класс белорусской школы. Отвечай по-русски, по существу, '
        'только по приведённому тексту учебника, ничего не выдумывай. '
        'Оформляй markdown: заголовки, списки, таблицы. '
        'Указывай страницы учебника, если они видны в тексте '
        '(маркеры «--- стр. N ---»). Не пиши «по тексту учебника» и '
        'не переписывай исходник дословно.\n\n';

    switch (mode) {
      case modeRules:
        return '$base'
            'Собери из параграфа все правила, определения, теоремы, '
            'формулы и выводы. Для каждого укажи страницу учебника '
            'и краткий пример, если он есть. Отвечай списком: '
            '«**Правило/теорема** (с. N) — формулировка + пример».';
      case modeTasks:
        return '$base'
            'Разбери задания/упражнения из параграфа. Каждое задание: '
            'краткая постановка, какое правило/теорема применяется '
            '((с. N), если видно), решение по шагам, ответ. '
            'Оформляй: «**Задание N.** … → **Решение:** … → **Ответ:** …».';
      case modeAnswers:
        return '$base'
            'Дай развёрнутые ответы на вопросы в конце параграфа '
            '(если вопросов нет — ключевые вопросы по теме). Ответ — '
            'кратко, по пунктам, со ссылками на страницы.';
      case modeSummary:
        return '$base'
            'Это произведение литературы (или его фрагмент). Дай краткое '
            'содержание, главных героев, тему, идею и ключевые моменты '
            'для конспекта. Структура: «**Краткое содержание**», '
            '«**Герои**», «**Тема и идея**», «**Что выписать в конспект**».';
      case modeConspectus:
      default:
        return '$base'
            'Составь конспект параграфа для школьной тетради 11 класса: '
            '1) план параграфа (пункты); '
            '2) главное по пунктам плана: определения, правила, даты, '
            'формулы — с указанием страниц; '
            '3) вывод. Оформляй коротко, тезисно, чтобы было удобно '
            'переписывать от руки.';
    }
  }

  /// Очистка конспекта параграфа.
  Future<void> clearParagraphContent(String id) async {
    final p = _pbox.get(id);
    if (p == null) return;
    await _pbox.put(id, p.copyWith(content: '', updatedAt: DateTime.now()));
    _emit();
  }
}

final studyProvider =
    NotifierProvider<StudyController, StudyState>(StudyController.new);
