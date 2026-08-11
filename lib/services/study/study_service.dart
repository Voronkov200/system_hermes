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
  /// Порядок в учебнике (для сортировки).
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

/// Состояние модуля «Учёба».
class StudyState {
  final List<StudySubject> subjects;
  final List<StudyParagraph> paragraphs;
  final bool busy;
  final String? error;
  /// id параграфа, который сейчас разбирает LLM.
  final String? workingId;
  /// Прогресс загрузки встроенных разборов учебников (bundled).
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

  /// Версия встроенных разборов: при смене данные модуля пересобираются.
  static const int _bundleVersion = 2;

  /// Явная карта «книга (id из имени файла) → предмет каталога».
  /// Исключает слияние нескольких книг/версий в один предмет.
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

  /// Книги, которые не входят в программу (ВОВ, сборники задач, старые
  /// издания, дубли на другом языке) — при автоимпорте пропускаются.
  static const Set<String> _excludedBookIds = {
    '1014', '1025', '1027', // Великая Отечественная война (отдельное пособие)
    '903', '924', '949', '959', // сборники задач по алгебре/геометрии
    '1037', '1057', // сборники задач по физике
    '1040', '1044', // сборники задач по химии
    '917', '946', // старый английский (без частей, дубли Юхнель 2021)
    '776', '777', '911', '913', // немецкий
    '730', '770', '798', // французский
    '939', '945', '965', // испанский
    '1177', // китайский
    '804', '806', '809', '810', // допризывная/медицинская подготовка
    '916', '901', '905', '898', '922', '896', '931', '918', '940', // бел. дубли
    '1172', '1188', // история на белорусском (дубли частей)
  };

  @override
  StudyState build() {
    _box = Hive.box<StudySubject>(BoxNames.study);
    _pbox = Hive.box<StudyParagraph>(BoxNames.studyParagraphs);
    _checkBundleVersion();
    _ensureCatalog();
    if (!_bundledStarted && _pbox.isEmpty) {
      _bundledStarted = true;
      importBundledBooks();
    }
    return StudyState(
      subjects: _sortedSubjects(),
      paragraphs: _pbox.values.toList(),
    );
  }

  /// Сброс модуля «Учёба» при смене версии встроенных разборов:
  /// старые предметы/параграфы удаляются, каталог и разборы
  /// пересоздаются заново.
  void _checkBundleVersion() {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getInt('study_bundle_v') == _bundleVersion) return;
    for (final key in _box.keys.toList()) {
      _box.delete(key);
    }
    for (final key in _pbox.keys.toList()) {
      _pbox.delete(key);
    }
    prefs.setInt('study_bundle_v', _bundleVersion);
  }

  /// Создаёт предметы каталога при первом запуске и обновляет подписи
  /// (авторы, иконки) для уже существующих каталоговых предметов.
  void _ensureCatalog() {
    // Удаляем предметы, исключённые из каталога (старые названия,
    // Допризывная подготовка), вместе с их параграфами.
    for (final s in _box.values.toList()) {
      if (s.title == 'Допризывная подготовка' ||
          s.title == 'История Беларуси' ||
          s.title == 'Всемирная история' ||
          s.title == 'Английский язык') {
        _box.delete(s.id);
        for (final p in _pbox.values.where((p) => p.subjectId == s.id)) {
          _pbox.delete(p.id);
        }
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
      ..sort((a, b) => a.order.compareTo(b.order));
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
      order: _nextOrder(subject.id),
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
  // Импорт готового разбора учебника (JSON с ПК / встроенные разборы)
  // ------------------------------------------------------------------

  /// Импорт JSON из tool/study_parse: предмет + параграфы с текстом.
  /// Сопоставляет название с каталогом по имени PDF-файла.
  Future<StudySubject> importParsedBook(String jsonPath) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final raw = await File(jsonPath).readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final subject = await _importParsedMap(data);
      if (subject == null) {
        throw StateError('Книга не входит в список учебников 11 класса');
      }
      return subject;
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
      rethrow;
    }
  }

  /// Иностранные языки (кроме английского) и спецподготовка не входят
  /// в список учебников — такие файлы при импорте отклоняются.
  static const _excludedSubjects = [
    'немецкий', 'нямецкая', 'французский', 'французская', 'испанский',
    'іспанская', 'испанская', 'китайский', 'кітайская', 'итальянский',
    'польский', 'польская', 'иностранный язык',
    'допризывн', 'дапрызыўн', 'медицинск', 'медыцынск',
    'великая отечественная', 'айчынная вайна',
  ];

  /// id книги из имени файла («1155_История...pdf» → «1155»), или null.
  static String? _bookIdOf(String pdfName) {
    final m = RegExp(r'^(\d+)[_ ]').firstMatch(pdfName.trim());
    return m?.group(1);
  }

  Future<StudySubject?> _importParsedMap(
    Map<String, dynamic> data, {
    bool bundled = false,
  }) async {
    final pdfName = (data['file'] as String? ?? '').trim();
    final pdfLower = pdfName.toLowerCase();
    final method = (data['method'] as String? ?? '').trim();
    final paragraphList = (data['paragraphs'] as List? ?? const []);
    final bookId = _bookIdOf(pdfName);

    // Автоимпорт встроенных разборов: только книги из карты.
    if (bundled) {
      if (bookId == null ||
          _excludedBookIds.contains(bookId) ||
          !_bookCatalogMap.containsKey(bookId)) {
        return null;
      }
      final catalogTitle = _bookCatalogMap[bookId]!;
      final catalogItem = studyCatalog
          .firstWhere((i) => i.title == catalogTitle);
      return _importBook(catalogItem, paragraphList, method);
    }

    for (final marker in _excludedSubjects) {
      if (pdfLower.contains(marker) &&
          !pdfLower.contains('английский') &&
          !pdfLower.contains('англійская')) {
        throw StateError(
          '«$pdfName»: предмет не входит в список учебников 11 класса',
        );
      }
    }

    final catalogTitle = bookId == null ? null : _bookCatalogMap[bookId];
    if (catalogTitle != null) {
      final catalogItem = studyCatalog
          .firstWhere((i) => i.title == catalogTitle);
      return _importBook(catalogItem, paragraphList, method);
    }

    final catalogItem = _matchCatalog(pdfLower);
    final subject = await _subjectForPdf(pdfName, pdfLower, catalogItem, method);
    final now = DateTime.now();
    var order = _nextOrder(subject.id);
    for (final item in paragraphList) {
      final m = item as Map<String, dynamic>;
      final title = (m['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      final exists = _pbox.values
          .any((p) => p.subjectId == subject.id && p.title == title);
      if (exists) continue;
      final pid = genId();
      await _pbox.put(
        pid,
        StudyParagraph(
          id: pid,
          subjectId: subject.id,
          title: title,
          chapter: (m['chapter'] as String? ?? '').trim(),
          pages: (m['pages'] as String? ?? '').trim(),
          sourceText: (m['text'] as String? ?? '').trim(),
          updatedAt: now,
          order: order++,
        ),
      );
    }
    state = state.copyWith(busy: false, clearError: true);
    _emit();
    return subject;
  }

  /// Импорт книги в предмет каталога (общий путь для встроенных и
  /// импортированных разборов). Параграфы дописываются в конец предмета.
  Future<StudySubject> _importBook(
    StudyCatalogItem item,
    List<dynamic> paragraphList,
    String method,
  ) async {
    StudySubject? subject;
    for (final s in _box.values) {
      if (s.title == item.title) {
        subject = s;
        break;
      }
    }
    subject ??= await addSubject(
      title: item.title,
      icon: item.icon,
      kind: item.kind,
      category: item.category,
      subtitle: item.subtitle,
    );
    final s = subject!;
    final now = DateTime.now();
    var order = _nextOrder(s.id);
    for (final raw in paragraphList) {
      final m = raw as Map<String, dynamic>;
      final title = (m['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      final exists = _pbox.values
          .any((p) => p.subjectId == s.id && p.title == title);
      if (exists) continue;
      final pid = genId();
      await _pbox.put(
        pid,
        StudyParagraph(
          id: pid,
          subjectId: s.id,
          title: title,
          chapter: (m['chapter'] as String? ?? '').trim(),
          pages: (m['pages'] as String? ?? '').trim(),
          sourceText: (m['text'] as String? ?? '').trim(),
          updatedAt: now,
          order: order++,
        ),
      );
    }
    _emit();
    return s;
  }

  /// Следующий порядковый номер параграфа в предмете.
  int _nextOrder(String subjectId) {
    var max = 0;
    for (final p in _pbox.values) {
      if (p.subjectId == subjectId && p.order > max) max = p.order;
    }
    return max + 1;
  }

  /// Автоимпорт встроенных разборов учебников из assets/study/.
  /// Запускается один раз при первом открытии модуля, если база пуста.
  Future<void> importBundledBooks() async {
    try {
      final manifest =
          await rootBundle.loadString('assets/study/manifest.txt');
      final names = manifest
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.endsWith('.json'))
          .toList()
        ..sort((a, b) {
          final ai = int.tryParse(a.split('_').first) ?? 0;
          final bi = int.tryParse(b.split('_').first) ?? 0;
          return ai.compareTo(bi);
        });
      state = state.copyWith(
        busy: true,
        error: null,
        bundledDone: 0,
        bundledTotal: names.length,
      );
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
        state = state.copyWith(
          error: 'Пропущено разборов: ${skipped.length} '
              '(${skipped.take(2).join('; ')})',
        );
      }
    } catch (e) {
      state = state.copyWith(busy: false, error: 'Автоимпорт: $e');
    }
  }

  /// Поиск предмета каталога по имени PDF-файла (подстрокой).
  StudyCatalogItem? _matchCatalog(String pdfNameLower) {
    if (pdfNameLower.isEmpty) return null;
    for (final item in studyCatalog) {
      final part = item.title.contains('часть 1')
          ? 1
          : item.title.contains('часть 2')
              ? 2
              : 0;
      if (part > 0) {
        final hasPart = RegExp(r'ч\.?\s*\d|часть\s*\d').hasMatch(pdfNameLower);
        final matchesPart = hasPart
            ? RegExp('ч\\.?\\s*$part|часть\\s*$part').hasMatch(pdfNameLower)
            : item.title.toLowerCase() == pdfNameLower;
        if (!matchesPart) continue;
      }
      if (pdfNameLower.contains(item.title.toLowerCase())) return item;
      for (final a in item.aliases) {
        if (pdfNameLower.contains(a)) return item;
      }
    }
    return null;
  }

  /// Предмет для PDF: существующий из каталога или созданный по имени файла.
  Future<StudySubject> _subjectForPdf(
    String pdfName,
    String pdfLower,
    StudyCatalogItem? catalogItem,
    String method,
  ) async {
    if (catalogItem != null) {
      for (final s in _box.values) {
        if (s.title == catalogItem.title) return s;
      }
      return addSubject(
        title: catalogItem.title,
        icon: catalogItem.icon,
        kind: catalogItem.kind,
        category: catalogItem.category,
        subtitle: catalogItem.subtitle,
      );
    }
    final clean = _cleanPdfTitle(pdfName, pdfLower);
    for (final s in _box.values) {
      if (s.title == clean) return s;
    }
    final isGuide = pdfLower.contains('сборник') ||
        pdfLower.contains('зборнік') ||
        pdfLower.contains('хрестоматия') ||
        pdfLower.contains('хрэстаматыя') ||
        pdfLower.contains('справочник') ||
        pdfLower.contains('даведнік') ||
        pdfLower.contains('пособие') ||
        pdfLower.contains('дапаможнік');
    return addSubject(
      title: clean,
      icon: 'book',
      kind: isGuide ? 'guide' : 'subject',
      category: isGuide ? 'Дополнительная литература' : 'Импортированные',
      subtitle: method.isEmpty ? '' : 'готовый разбор · $method',
    );
  }

  /// Чистое название предмета из имени PDF-файла.
  static String _cleanPdfTitle(String pdfName, String pdfLower) {
    String t;
    final idx = pdfLower.indexOf('_');
    if (idx >= 0 && RegExp(r'^\d+$').hasMatch(pdfLower.substring(0, idx))) {
      t = pdfName.substring(idx + 1).replaceAll('.pdf', '');
    } else {
      t = pdfName.replaceAll('.pdf', '');
    }
    final suffix = RegExp(
        r'_(учебное пособие|вучэбны дапаможнік|учебник|падручнік|навучальны дапаможнік|пособие|дапаможнік|учебное пособие\.\s*ч\.\s*\d+)$',
        caseSensitive: false);
    t = t.replaceAll(suffix, '');
    t = t.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
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
  /// Возвращает число созданных параграфов.
  Future<int> parsePdf(StudySubject subject) async {
    if (subject.filePath == null) {
      throw Exception('К предмету не прикреплён PDF-учебник.');
    }
    state = state.copyWith(busy: true, error: null);
    try {
      final text = await extractPdfText(subject.filePath!);
      final parts = splitPdfToParagraphs(text);
      if (parts.isEmpty) {
        throw Exception(
          'Не удалось распознать текст учебника на параграфы: '
          'PDF извлечён, но заголовков §/Глава в тексте не нашлось. '
          'Возможно, это скан без OCR-слоя или разметка без параграфов '
          '(стр. 1–${_pageCount(text)}).',
        );
      }
      for (final part in parts) {
        final pid = genId();
        await _pbox.put(
          pid,
          StudyParagraph(
            id: pid,
            subjectId: subject.id,
            title: part.title,
            chapter: part.chapter,
            pages: part.pages,
            sourceText: part.text,
            updatedAt: DateTime.now(),
          ),
        );
      }
      state = state.copyWith(busy: false, clearError: true);
      _emit();
      return parts.length;
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
      rethrow;
    }
  }

  /// Полная пере-нарезка: старые параграфы удаляются.
  Future<int> reparsePdf(StudySubject subject) async {
    for (final p in _pbox.values.where((p) => p.subjectId == subject.id)) {
      await _pbox.delete(p.id);
    }
    return parsePdf(subject);
  }

  /// Число страниц по маркерам «--- стр. N ---» в извлечённом тексте.
  static int _pageCount(String text) {
    final re = RegExp(r'---\s*стр\.\s*(\d+)\s*---');
    final nums = re.allMatches(text).map((m) => int.parse(m.group(1)!));
    return nums.isEmpty ? 0 : nums.reduce((a, b) => a > b ? a : b);
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
            'и краткий пример, если он есть. Помечай, где правило '
            'применяется (в каком задании/упражнении параграфа, каком '
            'классе). Если правило взято из учебника другого класса или '
            'пособия — укажи это явной перекрёстной ссылкой на источник. '
            'Отвечай списком: «**Правило/теорема** (с. N) — формулировка '
            '+ пример + где применяется».';
      case modeTasks:
        return '$base'
            'Разбери задания/упражнения из параграфа. Каждое задание '
            'разбито на пункты (а, б, в, …) — для каждого пункта своё '
            'решение по шагам и свой ответ. Указывай, какое '
            'правило/теорема применяется ((с. N), если видно). '
            'Оформляй: «**Задание N.** постановка → **а) Решение:** … → '
            '**Ответ:** …» — отдельно для каждого пункта.';
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
            '«**Герои**», «**Тема и идея**», «**Ключевые цитаты**», '
            '«**Что выписать в конспект**».';
      case modeConspectus:
      default:
        return '$base'
            'Составь конспект параграфа для школьной тетради 11 класса: '
            '1) план параграфа (пункты) — для истории обязательно; '
            '2) главное по пунктам плана: определения, правила, даты, '
            'формулы — короткими тезисами, пригодными для переписывания '
            'от руки, с указанием страниц; '
            '3) если в параграфе есть вопросы после текста — перечисли '
            'их в конце и дай краткий ответ на каждый; '
            '4) вывод. Не сплошной текст — только тезисы и списки.';
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
