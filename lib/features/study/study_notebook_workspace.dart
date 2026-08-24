// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, prefer_const_declarations

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../services/settings_service.dart';
import '../../services/study/local_study_content.dart';
import '../../services/study/resheba_service.dart';
import '../../services/study/study_content_quality.dart';
import '../../services/study/study_note_persistence.dart';
import '../../services/study/study_note_template.dart';
import '../../services/study/study_service.dart';
import '../../services/study/study_textbook_catalog.dart';
import '../../services/study/study_textbook_page_image_service.dart';
import 'resheba_screen.dart';

class StudyNotebookScreen extends ConsumerWidget {
  final String paragraphId;
  final StudyParagraph? initial;

  const StudyNotebookScreen({
    super.key,
    required this.paragraphId,
    this.initial,
  });

  StudyParagraph? _paragraph(List<StudyParagraph> all) {
    for (final item in all) {
      if (item.id == paragraphId) return item;
    }
    return initial;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studyProvider);
    final study = ref.read(studyProvider.notifier);
    final paragraph = _paragraph(state.paragraphs);
    if (paragraph == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Параграф')),
        body: Center(child: Text('Параграф не найден')),
      );
    }

    final subject = study.subjectOf(paragraph.subjectId);
    final title = subject?.title ?? 'Учёба';
    final local = LocalStudyContent.build(
      paragraph.sourceText,
      analysis: subject?.analysis ?? 'humanities',
    );
    final note = StudyNoteTemplateEngine.build(
      subjectTitle: title,
      sourceText: paragraph.sourceText,
      local: local,
    );
    final range = StudyTextbookCatalog.rangeFor(
      chapter: paragraph.chapter,
      pages: paragraph.pages,
      subjectTitle: subject?.title,
      siblings: state.paragraphs
          .where((item) => item.subjectId == paragraph.subjectId)
          .map((item) => (chapter: item.chapter, pages: item.pages)),
    );
    final prefs = ref.read(sharedPreferencesProvider);
    final hasGdz = subject != null &&
        ReshebaService.jsPathFor(subject.title) != null;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            paragraph.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Выучено',
              onPressed: () => study.toggleLearned(paragraph.id),
              icon: Icon(
                paragraph.learned
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: paragraph.learned ? AppColors.accent : null,
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.notes_rounded), text: 'Конспект'),
              Tab(icon: Icon(Icons.menu_book_rounded), text: 'Учебник'),
              Tab(icon: Icon(Icons.photo_library_outlined), text: 'ГДЗ'),
              Tab(icon: Icon(Icons.psychology_alt_outlined), text: 'Повторение'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NotesView(
              paragraph: paragraph,
              subjectTitle: title,
              note: note,
              quality: StudyContentQuality.inspect(paragraph.sourceText),
              prefs: prefs,
            ),
            _BookView(range: range),
            _GdzView(subject: subject, available: hasGdz),
            _ReviewView(
              paragraphId: paragraph.id,
              note: note,
              prefs: prefs,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesView extends StatelessWidget {
  final StudyParagraph paragraph;
  final String subjectTitle;
  final StudyNoteTemplate note;
  final StudySourceReport quality;
  final SharedPreferences prefs;

  const _NotesView({
    required this.paragraph,
    required this.subjectTitle,
    required this.note,
    required this.quality,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final question = note.selfCheck.isNotEmpty
        ? note.selfCheck.first
        : 'Какова главная мысль темы?';
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _Header(
          subject: subjectTitle,
          topic: paragraph.title,
          pages: paragraph.pages,
          question: question,
          chain: note.memoryChain,
        ),
        SizedBox(height: 10),
        _Quality(report: quality),
        SizedBox(height: 10),
        for (final section in note.sections) ...[
          _Section(section: section),
          SizedBox(height: 9),
        ],
        if (note.methodSteps.isNotEmpty) ...[
          _Algorithm(steps: note.methodSteps),
          SizedBox(height: 9),
        ],
        _PersonalFields(paragraphId: paragraph.id, prefs: prefs),
        SizedBox(height: 10),
        _Legend(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String subject;
  final String topic;
  final String pages;
  final String question;
  final String chain;

  const _Header({
    required this.subject,
    required this.topic,
    required this.pages,
    required this.question,
    required this.chain,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'СТРУКТУРИРОВАННЫЙ КОНСПЕКТ',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
            SizedBox(height: 9),
            Text('Дата: ${_date(now)}', style: TextStyle(fontSize: 12)),
            Text('Предмет: $subject', style: TextStyle(fontSize: 12)),
            Text('Тема: $topic', style: TextStyle(fontSize: 12)),
            if (pages.isNotEmpty)
              Text('Страницы: $pages', style: TextStyle(fontSize: 12)),
            Divider(height: 22),
            Text(
              'Главный вопрос темы',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
            SizedBox(height: 3),
            Text(
              question,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                chain,
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Quality extends StatelessWidget {
  final StudySourceReport report;

  const _Quality({required this.report});

  @override
  Widget build(BuildContext context) {
    final warning = report.quality != StudySourceQuality.ready;
    final color = warning ? AppColors.warning : AppColors.accent;
    return Container(
      padding: EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        '${report.label}. Формулы, таблицы и рисунки сверяй по оригинальной '
        'PNG-странице во вкладке «Учебник».',
        style: TextStyle(fontSize: 11.5, height: 1.4),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final StudyNoteSection section;

  const _Section({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Badge(section.marker),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            SizedBox(height: 9),
            if (section.items.isEmpty)
              Text(
                section.emptyHint,
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              for (final item in section.items)
                Padding(
                  padding: EdgeInsets.only(bottom: 7),
                  child: SelectableText(
                    '• $item',
                    style: TextStyle(fontSize: 12.5, height: 1.42),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String value;

  const _Badge(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: 29),
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.accent,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Algorithm extends StatelessWidget {
  final List<String> steps;

  const _Algorithm({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Алгоритм работы',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 9),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '${i + 1}. ${steps[i]}',
                  style: TextStyle(fontSize: 12.5, height: 1.38),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonalFields extends StatefulWidget {
  final String paragraphId;
  final SharedPreferences prefs;

  const _PersonalFields({required this.paragraphId, required this.prefs});

  @override
  State<_PersonalFields> createState() => _PersonalFieldsState();
}

class _PersonalFieldsState extends State<_PersonalFields> {
  late final TextEditingController example;
  late final TextEditingController conclusion;
  late final TextEditingController unclear;
  late final TextEditingController teacher;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    final data = StudyNotePersistence.readText(widget.prefs, widget.paragraphId);
    example = TextEditingController(text: data.ownExample);
    conclusion = TextEditingController(text: data.conclusion);
    unclear = TextEditingController(text: data.unclear);
    teacher = TextEditingController(text: data.teacherNotes);
  }

  @override
  void dispose() {
    example.dispose();
    conclusion.dispose();
    unclear.dispose();
    teacher.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final old = StudyNotePersistence.readText(widget.prefs, widget.paragraphId);
    await StudyNotePersistence.writeText(
      widget.prefs,
      widget.paragraphId,
      StudyNoteTextData(
        ownExample: example.text.trim(),
        conclusion: conclusion.text.trim(),
        unclear: unclear.text.trim(),
        teacherNotes: teacher.text.trim(),
        errors: old.errors,
      ),
    );
    if (mounted) setState(() => saved = true);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Мои дополнения',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 4),
            Text(
              'Сохраняются отдельно и не стираются при обновлении учебника.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
            SizedBox(height: 10),
            _Input(example, 'Мой собственный пример'),
            SizedBox(height: 9),
            _Input(conclusion, 'Мини-вывод (2–3 предложения)'),
            SizedBox(height: 9),
            _Input(unclear, 'Что я не понял'),
            SizedBox(height: 9),
            _Input(teacher, 'Дополнения учителя', lines: 3),
            SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _save,
              icon: Icon(saved ? Icons.check : Icons.save_outlined),
              label: Text(saved ? 'Сохранено' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int lines;

  const _Input(this.controller, this.label, {this.lines = 2});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: lines,
      maxLines: 6,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[
      ('!', 'важно'),
      ('?', 'непонятно'),
      ('Д', 'дата'),
      ('Ф', 'формула'),
      ('П', 'правило / понятие'),
      ('О', 'ошибка'),
      ('ПВ', 'повторить'),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final entry in entries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Badge(entry.$1),
                  SizedBox(width: 5),
                  Text(entry.$2, style: TextStyle(fontSize: 11)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BookView extends StatelessWidget {
  final StudyTextbookPageRange? range;

  const _BookView({required this.range});

  @override
  Widget build(BuildContext context) {
    if (range == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Оригинальная страница для этого параграфа пока не определена.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _BookPager(range: range!);
  }
}

class _BookPager extends ConsumerStatefulWidget {
  final StudyTextbookPageRange range;

  const _BookPager({required this.range});

  @override
  ConsumerState<_BookPager> createState() => _BookPagerState();
}

class _BookPagerState extends ConsumerState<_BookPager> {
  int index = 0;

  int get count => widget.range.pdfEnd - widget.range.pdfStart + 1;

  @override
  Widget build(BuildContext context) {
    final pdfPage = widget.range.pdfStart + index;
    final printed = widget.range.printedStart + index;
    final request = (bookId: widget.range.source.bookId, pdfPage: pdfPage);
    final asyncPage = ref.watch(studyTextbookPageImageProvider(request));
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.range.source.title} · стр. $printed · ${index + 1}/$count',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              _Badge('PNG'),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: asyncPage.when(
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$error', textAlign: TextAlign.center),
                    SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(
                        studyTextbookPageImageProvider(request),
                      ),
                      child: Text('Повторить'),
                    ),
                  ],
                ),
              ),
              data: (file) => GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _FullPage(file: file, page: printed),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  child: Image.file(file, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: index > 0 ? () => setState(() => index--) : null,
                  child: Text('Назад'),
                ),
              ),
              SizedBox(width: 9),
              Expanded(
                child: FilledButton(
                  onPressed:
                      index + 1 < count ? () => setState(() => index++) : null,
                  child: Text('Дальше'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FullPage extends StatelessWidget {
  final File file;
  final int page;

  const _FullPage({required this.file, required this.page});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Страница $page')),
      backgroundColor: Colors.black,
      body: InteractiveViewer(
        minScale: .7,
        maxScale: 5,
        child: Center(child: Image.file(file)),
      ),
    );
  }
}

class _GdzView extends StatelessWidget {
  final StudySubject? subject;
  final bool available;

  const _GdzView({required this.subject, required this.available});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined, size: 40, color: AppColors.accent),
                SizedBox(height: 10),
                Text(
                  available ? 'Оригинальные фото решений' : 'ГДЗ не подключено',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 7),
                Text(
                  available
                      ? 'Выбери раздел и номер. Открытые решения сохраняются на телефоне.'
                      : 'Для этого предмета пока нет настроенного источника решений.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
                if (available && subject != null) ...[
                  SizedBox(height: 13),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReshebaScreen(
                          subjectTitle: subject!.title,
                          subjectId: subject!.id,
                        ),
                      ),
                    ),
                    child: Text('Открыть решения'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  final String paragraphId;
  final StudyNoteTemplate note;
  final SharedPreferences prefs;

  const _ReviewView({
    required this.paragraphId,
    required this.note,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _Questions(note.selfCheck),
        SizedBox(height: 10),
        _ReviewSchedule(paragraphId: paragraphId, prefs: prefs),
        SizedBox(height: 10),
        _Errors(paragraphId: paragraphId, prefs: prefs),
        SizedBox(height: 10),
        _LearnedCriteria(),
      ],
    );
  }
}

class _Questions extends StatefulWidget {
  final List<String> questions;

  const _Questions(this.questions);

  @override
  State<_Questions> createState() => _QuestionsState();
}

class _QuestionsState extends State<_Questions> {
  late List<bool> done;

  @override
  void initState() {
    super.initState();
    done = List<bool>.filled(widget.questions.length, false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Самопроверка без учебника',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 5),
            Text(
              'Ответь вслух или письменно до открытия страницы учебника.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
            for (var i = 0; i < widget.questions.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: done[i],
                onChanged: (value) => setState(() => done[i] = value ?? false),
                title: Text(widget.questions[i], style: TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewSchedule extends StatefulWidget {
  final String paragraphId;
  final SharedPreferences prefs;

  const _ReviewSchedule({required this.paragraphId, required this.prefs});

  @override
  State<_ReviewSchedule> createState() => _ReviewScheduleState();
}

class _ReviewScheduleState extends State<_ReviewSchedule> {
  late StudyReviewData data;

  @override
  void initState() {
    super.initState();
    data = StudyNotePersistence.readReview(widget.prefs, widget.paragraphId);
  }

  Future<void> _start() async {
    final next = StudyReviewData(startedAt: DateTime.now());
    await StudyNotePersistence.writeReview(widget.prefs, widget.paragraphId, next);
    if (mounted) setState(() => data = next);
  }

  Future<void> _complete() async {
    if (data.startedAt == null ||
        data.completedStages >= StudyNotePersistence.reviewIntervals.length) {
      return;
    }
    final next = StudyReviewData(
      startedAt: data.startedAt,
      completedStages: data.completedStages + 1,
    );
    await StudyNotePersistence.writeReview(widget.prefs, widget.paragraphId, next);
    if (mounted) setState(() => data = next);
  }

  @override
  Widget build(BuildContext context) {
    final nextAt = StudyNotePersistence.nextReviewAt(data);
    final finished =
        data.completedStages >= StudyNotePersistence.reviewIntervals.length;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'График повторения',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            for (var i = 0; i < StudyNotePersistence.reviewIntervals.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  i < data.completedStages
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: i < data.completedStages
                      ? AppColors.accent
                      : AppColors.textDim,
                ),
                title: Text(
                  StudyNotePersistence.stageLabel(i),
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (data.startedAt == null)
              FilledButton(onPressed: _start, child: Text('Начать повторения'))
            else if (!finished) ...[
              if (nextAt != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Следующее: ${_dateTime(nextAt)}',
                    style: TextStyle(color: AppColors.cyan, fontSize: 12),
                  ),
                ),
              FilledButton(onPressed: _complete, child: Text('Этап выполнен')),
            ] else
              Text(
                'Все 5 этапов пройдены — проведи контрольную самопроверку.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }
}

class _Errors extends StatefulWidget {
  final String paragraphId;
  final SharedPreferences prefs;

  const _Errors({required this.paragraphId, required this.prefs});

  @override
  State<_Errors> createState() => _ErrorsState();
}

class _ErrorsState extends State<_Errors> {
  late List<String> errors;

  @override
  void initState() {
    super.initState();
    errors = List<String>.from(
      StudyNotePersistence.readText(widget.prefs, widget.paragraphId).errors,
    );
  }

  Future<void> _persist() async {
    final old = StudyNotePersistence.readText(widget.prefs, widget.paragraphId);
    await StudyNotePersistence.writeText(
      widget.prefs,
      widget.paragraphId,
      StudyNoteTextData(
        ownExample: old.ownExample,
        conclusion: old.conclusion,
        teacherNotes: old.teacherNotes,
        unclear: old.unclear,
        errors: errors,
      ),
    );
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Моя ошибка'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Что было неправильно и как сделать правильно?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    setState(() => errors.add(value));
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Мои ошибки',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(onPressed: _add, icon: Icon(Icons.add_circle_outline)),
              ],
            ),
            if (errors.isEmpty)
              Text(
                'Записывай сюда ошибки из задач, правил и самопроверок.',
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              )
            else
              for (var i = 0; i < errors.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _Badge('О'),
                  title: Text(errors[i], style: TextStyle(fontSize: 12.5)),
                  trailing: IconButton(
                    onPressed: () async {
                      setState(() => errors.removeAt(i));
                      await _persist();
                    },
                    icon: Icon(Icons.close, size: 18),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LearnedCriteria extends StatelessWidget {
  const _LearnedCriteria();

  @override
  Widget build(BuildContext context) {
    final items = [
      'объяснить тему без учебника',
      'привести собственный пример',
      'решить типовое задание',
      'ответить на вопросы',
      'связать тему с предыдущей',
      'найти и исправить свою ошибку',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Тема выучена, если можешь:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text('✓ $item', style: TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) {
  final d = value.day.toString().padLeft(2, '0');
  final m = value.month.toString().padLeft(2, '0');
  return '$d.$m.${value.year}';
}

String _dateTime(DateTime value) {
  final h = value.hour.toString().padLeft(2, '0');
  final min = value.minute.toString().padLeft(2, '0');
  return '${_date(value)} · $h:$min';
}
