// Модуль «Учёба»: предметы 11 класса по белорусской школьной программе.
//
// Предмет (StudySubject) — из каталога [studyCatalog] либо добавленный
// вручную (в т.ч. дополнительная литература/пособия). К предмету
// прикрепляется PDF-учебник; его текст извлекается, режется на параграфы
// (StudyParagraph), каждый параграф разбирается LLM: конспект, план,
// правила/теоремы со страницами, решения заданий, ответы на вопросы,
// краткое содержание произведений.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
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
import 'study_content_quality.dart';

/// Предмет (или дополнительная литература) в «Учёбе».
@HiveType(typeId: 12)
class StudySubject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String icon;
  @HiveField(3)
  final String kind;
  @HiveField(4)
  final String category;
  @HiveField(5)
  final String subtitle;
  @HiveField(6)
  final String analysis;
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
  @HiveField(3)
  final String chapter;
  @HiveField(4)
  final String pages;
  @HiveField(5)
  final String sourceText;
  @HiveField(6)
  final String content;
  @HiveField(7)
  final bool learned;
  @HiveField(8)
  final DateTime updatedAt;
  @HiveField(9)
  final int order;

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
    this.order = 0,
  });

  StudyParagraph copyWith({
    String? title,
    String? chapter,
    String? pages,
    String? sourceText,
    String? content,
    bool? learned,
    DateTime? updatedAt,
    int? order,
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
        order: order ?? this.order,
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
        order: reader.readInt(),
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
      ..writeInt(obj.updatedAt.millisecondsSinceEpoch)
      ..writeInt(obj.order);
  }
}

class StudyState {
  final List<StudySubject> subjects;
  final List<StudyParagraph> paragraphs;
  final bool busy;
  final String? error;
  final String? workingId;
  final int bundledDone;
  final int bundledTotal;

  const StudyState({
    this.subjects = const [],
    this.paragraphs = const [],
    this.busy = false,
    this.error,
    this.workingId,
    this.bundledDone = 0,
    this.bundledTotal = 0,
  });

  StudyState copyWith({
    List<StudySubject>? subjects,
    List<StudyParagraph>? paragraphs,
    bool? busy,
    String? error,
    bool clearError = false,
    String? workingId,
    bool clearWorking = false,
    int? bundledDone,
    int? bundledTotal,
  }) =>
      StudyState(
        subjects: subjects ?? this.subjects,
        paragraphs: paragraphs ?? this.paragraphs,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        workingId: clearWorking ? null : (workingId ?? this.workingId),
        bundledDone: bundledDone ?? this.bundledDone,
        bundledTotal: bundledTotal ?? this.bundledTotal,
      );
}

/// Контроллер «Учёбы»: каталог, параграфы, LLM-разбор.
class StudyController extends Notifier<StudyState> {
  late final Box<StudySubject> _box;
  late final Box<StudyParagraph> _pbox;
  bool _bundledStarted = false;
  bool _bundleNeedsRefresh = false;

  static const int _bundleVersion = 3;

  static const Map<String, String> _bookCatalogMap = {
    '1155': 'История (часть 1)',
    '1176': 'История (часть 2)',
    '938': 'Обществоведение',
    '920': 'Беларуская мова',
    '904': 'Беларуская літаратура',
    '1202': 'Беларуская літаратура',
    '914': 'Русский язык',
    '915': 'Русская литература',
    '1207': 'Русская литература',
    '1208': 'Русская литература',
    '986': 'Английский язык (часть 1)',
    '1015': 'Английский язык (часть 2)',
    '894': 'Алгебра',
    '902': 'Геометрия',
    '900': 'Физика',
    '899': 'Химия',
    '921': 'Биология',
    '897': 'География',
    '923': 'Информатика',
    '888': 'Астрономия',
  };

  static const Set<String> _excludedBookIds = {
    '1014', '1025', '1027', '903', '924', '949', '959', '1037', '1057',
    '1040', '1044', '917', '946', '776', '777', '911', '913', '730', '770',
    '798', '939', '945', '965', '1177', '804', '806', '809', '810', '916',
    '901', '905', '898', '922', '896', '931', '918', '940', '1172', '1188',
  };

  @override
  StudyState build() {
    _box = Hive.box<StudySubject>(BoxNames.study);
    _pbox = Hive.box<StudyParagraph>(BoxNames.studyParagraphs);
    _checkBundleVersion();
    _ensureCatalog();
    if (!_bundledStarted && (_pbox.isEmpty || _bundleNeedsRefresh)) {
      _bundledStarted = true;
      _bundleNeedsRefresh = false;
      importBundledBooks();
    }
    return StudyState(
      subjects: _sortedSubjects(),
      paragraphs: _pbox.values.toList(),
    );
  }

  /// Проверяет версию встроенного контента, но НИКОГДА не удаляет
  /// пользовательские данные. Новая версия только запускает идемпотентный
  /// импорт: существующие параграфы сохраняются, новые добавляются.
  void _checkBundleVersion() {
    final prefs = ref.read(sharedPreferencesProvider);
    final previous = prefs.getInt('study_bundle_v');
    if (previous == _bundleVersion) return;
    _bundleNeedsRefresh = true;
    // В старой реализации здесь очищались обе Hive-базы. Это уничтожало
    // импортированные книги, конспекты и флаг learned при обновлении APK.
    // Версия теперь является только маркером контента.
    prefs.setInt('study_bundle_v', _bundleVersion);
  }

  void _ensureCatalog() {
    for (final s in _box.values.toList()) {
      if (s.title == 'Допризывная подготовка' ||
          s.title == 'История Беларуси' ||
          s.title == 'Всемирная история' ||
          s.title == 'Английский язык') {
        // Не удаляем предмет автоматически: пользователь мог добавить в него
        // собственный PDF/конспект. Оставляем его как пользовательские данные.
        continue;
      }
    }
    for (final item in studyCatalog) {
      StudySubject? existing;
      for (final s in _box.values) {
        if (s.title == item.title) {
          existing = s;
          break;
        }
      }
      if (existing == null) {
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
      } else if (existing.subtitle != item.subtitle ||
          existing.icon != item.icon ||
          existing.category != item.category) {
        _box.put(
          existing.id,
          existing.copyWith(
            subtitle: item.subtitle,
            icon: item.icon,
            category: item.category,
          ),
        );
      }
    }
  }

  static String _analysisFor(String title) {
    const lit = ['литератур', 'літаратур'];
    if (lit.any(title.toLowerCase().contains)) return 'literature';
    const exact = ['алгебра', 'геометрия', 'физика', 'химия', 'биология', 'информатика', 'астрономия', 'математика'];
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

  void _emit() => state = state.copyWith(
        subjects: _sortedSubjects(),
        paragraphs: _pbox.values.toList(),
      );

  StudySubject? subjectOf(String id) {
    for (final s in _box.values) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<StudyParagraph> paragraphsOf(String subjectId) {
    final list = _pbox.values.where((p) => p.subjectId == subjectId).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  StudyParagraph? _paragraphById(String id) {
    final direct = _pbox.get(id);
    if (direct != null) return direct;
    for (final paragraph in _pbox.values) {
      if (paragraph.id == id) return paragraph;
    }
    return null;
  }

  /// Сохраняет запись по её id и заодно удаляет старый ошибочный Hive-ключ.
  /// В ранней версии импорта ключ и `StudyParagraph.id` создавались двумя
  /// разными вызовами `genId()`, поэтому обычный `_pbox.get(id)` не работал.
  Future<void> _putParagraph(StudyParagraph paragraph) async {
    final staleKeys = _pbox.keys
        .where(
          (key) => key != paragraph.id && _pbox.get(key)?.id == paragraph.id,
        )
        .toList();
    await _pbox.put(paragraph.id, paragraph);
    for (final key in staleKeys) {
      await _pbox.delete(key);
    }
  }

  Future<void> _deleteParagraphById(String id) async {
    final keys = _pbox.keys
        .where((key) => key == id || _pbox.get(key)?.id == id)
        .toList();
    for (final key in keys) {
      await _pbox.delete(key);
    }
  }

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
    final paragraphIds = _pbox.values
        .where((paragraph) => paragraph.subjectId == id)
        .map((paragraph) => paragraph.id)
        .toSet();
    for (final paragraphId in paragraphIds) {
      await _deleteParagraphById(paragraphId);
    }
    _emit();
  }

  Future<String> attachPdf(StudySubject subject, String srcPath) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final rootDir = await FileTools.root();
      final targetDir = Directory('${rootDir.path}/study');
      await targetDir.create(recursive: true);
      final ext = srcPath.split('.').last.toLowerCase();
      final target = '${targetDir.path}/${subject.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
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

  Future<StudyParagraph> addParagraph(StudySubject subject, {required String title, String chapter = '', String pages = '', String sourceText = ''}) async {
    final p = StudyParagraph(
      id: genId(),
      subjectId: subject.id,
      title: title.trim().isEmpty ? 'Без названия' : title.trim(),
      chapter: chapter,
      pages: pages,
      sourceText: sourceText,
      updatedAt: DateTime.now(),
      order: _nextOrder(subject.id),
    );
    await _pbox.put(p.id, p);
    _emit();
    return p;
  }

  StudyParagraph? _findImportedParagraph(String subjectId, String title) {
    final identity = StudyContentQuality.paragraphIdentity(
      subjectId: subjectId,
      title: title,
    );
    for (final paragraph in _pbox.values) {
      final candidate = StudyContentQuality.paragraphIdentity(
        subjectId: paragraph.subjectId,
        title: paragraph.title,
      );
      if (candidate == identity) return paragraph;
    }
    return null;
  }

  /// Идемпотентно обновляет распознанный источник, сохраняя пользовательский
  /// конспект, флаг изучения и стабильный id параграфа.
  Future<bool> _upsertImportedParagraph({
    required StudySubject subject,
    required String title,
    required String chapter,
    required String pages,
    required String sourceText,
    required int order,
  }) async {
    final existing = _findImportedParagraph(subject.id, title);
    if (existing != null) {
      final updated = existing.copyWith(
        chapter: chapter.isEmpty ? existing.chapter : chapter,
        pages: pages.isEmpty ? existing.pages : pages,
        sourceText: sourceText.isEmpty ? existing.sourceText : sourceText,
        updatedAt: DateTime.now(),
      );
      await _putParagraph(updated);
      return false;
    }

    final id = genId();
    await _pbox.put(
      id,
      StudyParagraph(
        id: id,
        subjectId: subject.id,
        title: title,
        chapter: chapter,
        pages: pages,
        sourceText: sourceText,
        updatedAt: DateTime.now(),
        order: order,
      ),
    );
    return true;
  }

  Future<void> updateParagraph(StudyParagraph p) async {
    await _putParagraph(p);
    _emit();
  }

  Future<void> toggleLearned(String id) async {
    final p = _paragraphById(id);
    if (p == null) return;
    await _putParagraph(
      p.copyWith(learned: !p.learned, updatedAt: DateTime.now()),
    );
    _emit();
  }

  Future<void> removeParagraph(String id) async {
    await _deleteParagraphById(id);
    _emit();
  }

  Future<StudySubject> importParsedBook(String jsonPath) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final raw = await File(jsonPath).readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final subject = await _importParsedMap(data);
      if (subject == null) throw StateError('Книга не входит в список учебников 11 класса');
      return subject;
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
      rethrow;
    }
  }

  static const _excludedSubjects = [
    'немецкий', 'нямецкая', 'французский', 'французская', 'испанский', 'іспанская', 'испанская', 'китайский', 'кітайская', 'итальянский', 'польский', 'польская', 'иностранный язык', 'допризывн', 'дапрызыўн', 'медицинск', 'медыцынск', 'великая отечественная', 'айчынная вайна',
  ];

  static String? _bookIdOf(String pdfName) {
    final m = RegExp(r'^(\d+)[_ ]').firstMatch(pdfName.trim());
    return m?.group(1);
  }

  Future<StudySubject?> _importParsedMap(Map<String, dynamic> data, {bool bundled = false}) async {
    final pdfName = (data['file'] as String? ?? '').trim();
    final pdfLower = pdfName.toLowerCase();
    final method = (data['method'] as String? ?? '').trim();
    final paragraphList = (data['paragraphs'] as List? ?? const []);
    final bookId = _bookIdOf(pdfName);

    if (bundled) {
      if (bookId == null || _excludedBookIds.contains(bookId) || !_bookCatalogMap.containsKey(bookId)) return null;
      final catalogTitle = _bookCatalogMap[bookId]!;
      final catalogItem = studyCatalog.firstWhere((i) => i.title == catalogTitle);
      return _importBook(catalogItem, paragraphList, method);
    }

    for (final marker in _excludedSubjects) {
      if (pdfLower.contains(marker) && !pdfLower.contains('английский') && !pdfLower.contains('англійская')) {
        throw StateError('«$pdfName»: предмет не входит в список учебников 11 класса');
      }
    }

    final catalogTitle = bookId == null ? null : _bookCatalogMap[bookId];
    if (catalogTitle != null) {
      final catalogItem = studyCatalog.firstWhere((i) => i.title == catalogTitle);
      return _importBook(catalogItem, paragraphList, method);
    }

    final catalogItem = _matchCatalog(pdfLower);
    final subject = await _subjectForPdf(pdfName, pdfLower, catalogItem, method);
    var order = _nextOrder(subject.id);
    for (final item in paragraphList) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final title = (m['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      final created = await _upsertImportedParagraph(
        subject: subject,
        title: title,
        chapter: (m['chapter'] as String? ?? '').trim(),
        pages: (m['pages'] as String? ?? '').trim(),
        sourceText: (m['text'] as String? ?? '').trim(),
        order: order,
      );
      if (created) order++;
    }
    state = state.copyWith(busy: false, clearError: true);
    _emit();
    return subject;
  }

  Future<StudySubject> _importBook(StudyCatalogItem item, List<dynamic> paragraphList, String method) async {
    StudySubject? subject;
    for (final s in _box.values) {
      if (s.title == item.title) {
        subject = s;
        break;
      }
    }
    subject ??= await addSubject(title: item.title, icon: item.icon, kind: item.kind, category: item.category, subtitle: item.subtitle);
    final s = subject;
    var order = _nextOrder(s.id);
    for (final raw in paragraphList) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final title = (m['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      final created = await _upsertImportedParagraph(
        subject: s,
        title: title,
        chapter: (m['chapter'] as String? ?? '').trim(),
        pages: (m['pages'] as String? ?? '').trim(),
        sourceText: (m['text'] as String? ?? '').trim(),
        order: order,
      );
      if (created) order++;
    }
    _emit();
    return s;
  }

  int _nextOrder(String subjectId) {
    var max = 0;
    for (final p in _pbox.values) {
      if (p.subjectId == subjectId && p.order > max) max = p.order;
    }
    return max + 1;
  }

  Future<void> importBundledBooks() async {
    try {
      final manifest = await rootBundle.loadString('assets/study/manifest.txt');
      final names = manifest.split('\n').map((s) => s.trim()).where((s) => s.endsWith('.json')).toList()..sort((a, b) {
        final ai = int.tryParse(a.split('_').first) ?? 0;
        final bi = int.tryParse(b.split('_').first) ?? 0;
        return ai.compareTo(bi);
      });
      state = state.copyWith(busy: true, error: null, bundledDone: 0, bundledTotal: names.length);
      var done = 0;
      final skipped = <String>[];
      for (final name in names) {
        try {
          final content = await rootBundle.loadString('assets/study/$name');
          final data = jsonDecode(content) as Map<String, dynamic>;
          await _importParsedMap(data, bundled: true);
        } catch (e) {
          skipped.add('$name: $e');
        }
        done++;
        state = state.copyWith(bundledDone: done);
      }
      state = state.copyWith(busy: false, clearError: true);
      _emit();
      if (skipped.isNotEmpty) {
        state = state.copyWith(error: 'Пропущено разборов: ${skipped.length} (${skipped.take(2).join('; ')})');
      }
    } catch (e) {
      state = state.copyWith(busy: false, error: 'Автоимпорт: $e');
    }
  }

  StudyCatalogItem? _matchCatalog(String pdfNameLower) {
    if (pdfNameLower.isEmpty) return null;
    for (final item in studyCatalog) {
      final part = item.title.contains('часть 1') ? 1 : item.title.contains('часть 2') ? 2 : 0;
      if (part > 0) {
        final hasPart = RegExp(r'ч\.?\s*\d|часть\s*\d').hasMatch(pdfNameLower);
        final matchesPart = hasPart ? RegExp('ч\\.?\\s*$part|часть\\s*$part').hasMatch(pdfNameLower) : item.title.toLowerCase() == pdfNameLower;
        if (!matchesPart) continue;
      }
      if (pdfNameLower.contains(item.title.toLowerCase())) return item;
      for (final a in item.aliases) {
        if (pdfNameLower.contains(a)) return item;
      }
    }
    return null;
  }

  Future<StudySubject> _subjectForPdf(String pdfName, String pdfLower, StudyCatalogItem? catalogItem, String method) async {
    if (catalogItem != null) {
      for (final s in _box.values) {
        if (s.title == catalogItem.title) return s;
      }
      return addSubject(title: catalogItem.title, icon: catalogItem.icon, kind: catalogItem.kind, category: catalogItem.category, subtitle: catalogItem.subtitle);
    }
    final clean = _cleanPdfTitle(pdfName, pdfLower);
    for (final s in _box.values) {
      if (s.title == clean) return s;
    }
    final isGuide = pdfLower.contains('сборник') || pdfLower.contains('зборнік') || pdfLower.contains('хрестоматия') || pdfLower.contains('хрэстаматыя') || pdfLower.contains('справочник') || pdfLower.contains('даведнік') || pdfLower.contains('пособие') || pdfLower.contains('дапаможнік');
    return addSubject(title: clean, icon: 'book', kind: isGuide ? 'guide' : 'subject', category: isGuide ? 'Дополнительная литература' : 'Импортированные', subtitle: method.isEmpty ? '' : 'готовый разбор · $method');
  }

  static String _cleanPdfTitle(String pdfName, String pdfLower) {
    String t;
    final idx = pdfLower.indexOf('_');
    if (idx >= 0 && RegExp(r'^\d+$').hasMatch(pdfLower.substring(0, idx))) {
      t = pdfName.substring(idx + 1).replaceAll('.pdf', '');
    } else {
      t = pdfName.replaceAll('.pdf', '');
    }
    final suffix = RegExp(r'_(учебное пособие|вучэбны дапаможнік|учебник|падручнік|навучальны дапаможнік|пособие|дапаможнік|учебное пособие\.\s*ч\.\s*\d+)$', caseSensitive: false);
    t = t.replaceAll(suffix, '');
    t = t.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

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
    if (out.isEmpty) throw Exception('Текст из PDF не извлекается: вероятно, это скан без OCR-слоя.');
    if (out.length > maxChars) out = out.substring(0, maxChars);
    return out;
  }

  List<({String title, String chapter, String pages, String text})> splitPdfToParagraphs(String pdfText) {
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
      final title = heading ?? 'Параграф';
      String chapter = '';
      if (title.isNotEmpty) {
        final chRe = RegExp(r'^(Глава\s+\d+|Раздел\s+\d+|Часть\s+\d+)[.:]?\s*(.*)$', caseSensitive: false);
        final m = chRe.firstMatch(title);
        if (m != null) {
          chapter = m.group(1)!;
          final rest = m.group(2)?.trim() ?? '';
          if (rest.isNotEmpty) heading = rest;
        }
      }
      final pages = pageRe.allMatches(section).map((m) => m.group(1)).join(', ');
      final text = lines.skip(start).join('\n').replaceAll(pageRe, '').trim();
      if (text.isEmpty) continue;
      result.add((title: heading ?? title, chapter: chapter, pages: pages.isEmpty ? '' : 'с. $pages', text: text));
    }
    return result;
  }

  Future<int> parsePdf(StudySubject subject) async {
    if (subject.filePath == null) throw Exception('К предмету не прикреплён PDF-учебник.');
    state = state.copyWith(busy: true, error: null);
    try {
      final text = await extractPdfText(subject.filePath!);
      final parts = splitPdfToParagraphs(text);
      if (parts.isEmpty) throw Exception('Не удалось распознать текст учебника на параграфы. Возможно, это скан без OCR-слоя.');
      var order = _nextOrder(subject.id);
      var processed = 0;
      for (final part in parts) {
        final created = await _upsertImportedParagraph(
          subject: subject,
          title: part.title,
          chapter: part.chapter,
          pages: part.pages,
          sourceText: part.text,
          order: order,
        );
        if (created) order++;
        processed++;
      }
      state = state.copyWith(busy: false, clearError: true);
      _emit();
      return processed;
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
      rethrow;
    }
  }

  Future<int> reparsePdf(StudySubject subject) async {
    // Повторный разбор обновляет источник идемпотентно. Удаление здесь
    // уничтожало конспекты, прогресс и стабильные ссылки на параграфы.
    return parsePdf(subject);
  }

  static int _pageCount(String text) {
    final re = RegExp(r'---\s*стр\.\s*(\d+)\s*---');
    final nums = re.allMatches(text).map((m) => int.parse(m.group(1)!));
    return nums.isEmpty ? 0 : nums.reduce((a, b) => a > b ? a : b);
  }

  static const modeConspectus = 'conspectus';
  static const modeRules = 'rules';
  static const modeTasks = 'tasks';
  static const modeAnswers = 'answers';
  static const modeSummary = 'summary';

  Future<String> analyzeParagraph(StudyParagraph p, {String mode = modeConspectus}) async {
    final subject = subjectOf(p.subjectId);
    if (subject == null) throw Exception('Предмет не найден.');
    final report = StudyContentQuality.inspect(p.sourceText);
    if (!report.canAnalyze) {
      final message = '${report.label}. Прикрепи или повторно разбери PDF; '
          'Hermes не будет составлять материал только по названию темы.';
      state = state.copyWith(
        busy: false,
        error: message,
        workingId: p.id,
      );
      throw StateError(message);
    }
    final s = ref.read(settingsProvider);
    final source = StudyContentQuality.prepareForAnalysis(p.sourceText);
    final sys = _systemPrompt(subject, mode);
    final user = 'Учебник: ${subject.title}'
        '${subject.subtitle.isEmpty ? '' : ' (${subject.subtitle})'}\n'
        'Глава: ${p.chapter.isEmpty ? '—' : p.chapter}\n'
        'Параграф: ${p.title}'
        '${p.pages.isEmpty ? '' : ' · ${p.pages}'}\n'
        'Качество извлечения: ${report.label}.\n\n'
        'Текст параграфа:\n$source';
    state = state.copyWith(busy: true, error: null, workingId: p.id);
    try {
      final answer = await llmComplete(s, system: sys, user: user, maxTokens: 3000, timeoutSeconds: 180, temperature: 0.3);
      await _putParagraph(
        p.copyWith(content: answer, updatedAt: DateTime.now()),
      );
      state = state.copyWith(busy: false, clearError: true, clearWorking: true);
      return answer;
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e', workingId: p.id);
      rethrow;
    }
  }

  String _systemPrompt(StudySubject subject, String mode) {
    final base = 'Ты — репетитор по предмету «${subject.title}» за 11 класс '
        'белорусской школы. Используй только приведённый текст учебника. '
        'Не восстанавливай повреждённые OCR-формулы по догадке и не создавай '
        'несуществующие факты, номера, вопросы или задания. Если фрагмент '
        'нечитаем, прямо напиши «Не удалось надёжно распознать фрагмент». '
        'Оформляй результат корректным Markdown: заголовки и списки. Не '
        'используй псевдотаблицы с вертикальными чертами. Не выводи команды '
        'LaTeX вроде \\frac, \\sqrt и \\cdot: формулы записывай читаемым '
        'обычным текстом или Unicode. Страницу указывай только тогда, когда '
        'она подтверждена источником. Не переписывай исходник дословно.\n\n';
    switch (mode) {
      case modeRules:
        return '$base Собери правила, определения, теоремы, формулы и выводы. Для каждого укажи страницу, если она известна, и пример только если он есть в источнике.';
      case modeTasks:
        return '$base Найди только реально присутствующие задания. Сохрани '
            'исходные номера и подпункты а/б/в. Разбирай по схеме: точное '
            'условие → шаги решения → ответ. Если условие или формула '
            'повреждены, не решай задание и укажи причину.';
      case modeAnswers:
        return '$base Дай ответы только на вопросы, которые действительно '
            'присутствуют после параграфа. Если вопросов в источнике нет, '
            'так и напиши; не создавай свои вопросы в этом режиме.';
      case modeSummary:
        return '$base Для литературы дай краткое содержание, героев, тему, идею и ключевые моменты без выдуманных деталей.';
      case modeConspectus:
      default:
        return '$base Составь короткий конспект для тетради: цель темы, '
            '3–7 основных тезисов, точные определения/правила/даты/формулы '
            'из источника, один подтверждённый пример и итог. Не дублируй '
            'одну мысль в нескольких разделах.';
    }
  }

  Future<void> clearParagraphContent(String id) async {
    final p = _paragraphById(id);
    if (p == null) return;
    await _putParagraph(
      p.copyWith(content: '', updatedAt: DateTime.now()),
    );
    _emit();
  }
}

final studyProvider = NotifierProvider<StudyController, StudyState>(StudyController.new);
