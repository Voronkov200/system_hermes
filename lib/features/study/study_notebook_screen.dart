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

  StudyParagraph? _find(List<StudyParagraph> all) {
    for (final paragraph in all) {
      if (paragraph.id == paragraphId) return paragraph;
    }
    return initial;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studyProvider);
    final notifier = ref.read(studyProvider.notifier);
    final paragraph = _find(state.paragraphs);
    if (paragraph == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Параграф')),
        body: const Center(child: Text('Параграф не найден')),
      );
    }

    final subject = notifier.subjectOf(paragraph.subjectId);
    final subjectTitle = subject?.title ?? 'Учёба';
    final local = LocalStudyContent.build(
      paragraph.sourceText,
      analysis: subject?.analysis ?? 'humanities',
    );
    final template = StudyNoteTemplateEngine.build(
      subjectTitle: subjectTitle,
      sourceText: paragraph.sourceText,
      local: local,
    );
    final quality = StudyContentQuality.inspect(paragraph.sourceText);
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
              tooltip: paragraph.learned ? 'Отметить невыученным' : 'Выучено',
              onPressed: () => notifier.toggleLearned(paragraph.id),
              icon: Icon(
                paragraph.learned
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: paragraph.learned ? AppColors.accent : null,
              ),
            ),
            IconButton(
              tooltip: 'Удалить параграф',
              onPressed: () => _delete(context, ref, paragraph),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          bottom: const TabBar(
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
            _NotesTab(
              paragraph: paragraph,
              subjectTitle: subjectTitle,
              visibleChapter:
                  StudyTextbookCatalog.visibleChapter(paragraph.chapter),
              template: template,
              quality: quality,
              prefs: prefs,
            ),
            _BookTab(range: range),
            _GdzTab(subject: subject, available: hasGdz),
            _ReviewTab(
              paragraphId: paragraph.id,
              template: template,
              prefs: prefs,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StudyParagraph paragraph,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text('Удалить параграф «${paragraph.title}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(studyProvider.notifier).removeParagraph(paragraph.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _NotesTab extends StatelessWidget {
  final StudyParagraph paragraph;
  final String subjectTitle;
  final String visibleChapter;
  final StudyNoteTemplate template;
  final StudySourceReport quality;
  final SharedPreferences prefs;

  const _NotesTab({
    required this.paragraph,
    required this.subjectTitle,
    required this.visibleChapter,
    required this.template,
    required this.quality,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mainQuestion = template.selfCheck.isEmpty
        ? 'Какова главная мысль темы?'
        : template.selfCheck.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _NotebookHeader(
          date: _dateOnly(now),
          subject: subjectTitle,
          topic: paragraph.title,
          chapter: visibleChapter,
          pages: paragraph.pages,
          mainQuestion: mainQuestion,
          memoryChain: template.memoryChain,
        ),
        const SizedBox(height: 12),
        _SourceStatus(report: quality),
        const SizedBox(height: 12),
        for (final section in template.sections) ...[
          _NoteSectionCard(section: section),
          const SizedBox(height: 10),
        ],
        if (template.methodSteps.isNotEmpty) ...[
          _MethodCard(steps: template.methodSteps),
          const SizedBox(height: 10),
        ],
        _PersonalNotesEditor(
          paragraphId: paragraph.id,
          prefs: prefs,
        ),
        const SizedBox(height: 12),
        const _LegendCard(),
      ],
    );
  }
}

class _NotebookHeader extends StatelessWidget {
  final String date;
  final String subject;
  final String topic;
  final String chapter;
  final String pages;
  final String mainQuestion;
  final String memoryChain;

  const _NotebookHeader({
    required this.date,
    required this.subject,
    required this.topic,
    required this.chapter,
    required this.pages,
    required this.mainQuestion,
    required this.memoryChain,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'СТРУКТУРИРОВАННЫЙ КОНСПЕКТ',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 10),
            _MetaLine(label: 'Дата', value: date),
            _MetaLine(label: 'Предмет', value: subject),
            _MetaLine(label: 'Тема', value: topic),
            if (chapter.isNotEmpty) _MetaLine(label: 'Раздел', value: chapter),
            if (pages.isNotEmpty) _MetaLine(label: 'Страницы', value: pages),
            const Divider(height: 24),
            const Text(
              'Главный вопрос темы',
              style: TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
            const SizedBox(height: 4),
            Text(
              mainQuestion,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                memoryChain,
                style: const TextStyle(
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

class _MetaLine extends StatelessWidget {
  final String label;
  final String value;

  const _MetaLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              '$label:',
              style: const TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceStatus extends StatelessWidget {
  final StudySourceReport report;

  const _SourceStatus({required this.report});

  @override
  Widget build(BuildContext context) {
    final warning = report.quality != StudySourceQuality.ready;
    final color = warning ? AppColors.warning : AppColors.accent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.warning_amber_rounded : Icons.verified_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${report.label}. Факты берутся только из текста учебника; '
              'формулы, рисунки и таблицы сверяй во вкладке «Учебник».',
              style: const TextStyle(fontSize: 11.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteSectionCard extends StatelessWidget {
  final StudyNoteSection section;

  const _NoteSectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MarkerBadge(marker: section.marker),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    section.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (section.items.isEmpty)
              Text(
                section.emptyHint,
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              for (var i = 0; i < section.items.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == section.items.length - 1 ? 0 : 9,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: AppColors.accent)),
                      Expanded(
                        child: SelectableText(
                          section.items[i],
                          style: const TextStyle(fontSize: 12.5, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _MarkerBadge extends StatelessWidget {
  final String marker;

  const _MarkerBadge({required this.marker});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.accent.withValues(alpha: .3)),
      ),
      child: Text(
        marker,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final List<String> steps;

  const _MethodCard({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.route_outlined, color: AppColors.cyan),
                SizedBox(width: 9),
                Text(
                  'Алгоритм работы',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  '${i + 1}. ${steps[i]}',
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonalNotesEditor extends StatefulWidget {
  final String paragraphId;
  final SharedPreferences prefs;

  const _PersonalNotesEditor({
    required this.paragraphId,
    required this.prefs,
  });

  @override
  State<_PersonalNotesEditor> createState() => _PersonalNotesEditorState();
}

class _PersonalNotesEditorState extends State<_PersonalNotesEditor> {
  late final TextEditingController _example;
  late final TextEditingController _conclusion;
  late final TextEditingController _unclear;
  late final TextEditingController _teacher;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final data = StudyNotePersistence.readText(widget.prefs, widget.paragraphId);
    _example = TextEditingController(text: data.ownExample);
    _conclusion = TextEditingController(text: data.conclusion);
    _unclear = TextEditingController(text: data.unclear);
    _teacher = TextEditingController(text: data.teacherNotes);
  }

  @override
  void dispose() {
    _example.dispose();
    _conclusion.dispose();
    _unclear.dispose();
    _teacher.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = StudyNotePersistence.readText(
      widget.prefs,
      widget.paragraphId,
    );
    await StudyNotePersistence.writeText(
      widget.prefs,
      widget.paragraphId,
      StudyNoteTextData(
        ownExample: _example.text.trim(),
        conclusion: _conclusion.text.trim(),
        unclear: _unclear.text.trim(),
        teacherNotes: _teacher.text.trim(),
        errors: current.errors,
      ),
    );
    if (!mounted) return;
    setState(() => _saved = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.edit_note_rounded, color: AppColors.violet),
                SizedBox(width: 9),
                Text(
                  'Мои дополнения',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Эти поля принадлежат тебе и не стираются при обновлении учебника.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
            const SizedBox(height: 12),
            _NoteInput(
              controller: _example,
              label: 'Мой собственный пример',
              hint: 'Пример, задача, предложение или ситуация из жизни',
            ),
            const SizedBox(height: 10),
            _NoteInput(
              controller: _conclusion,
              label: 'Мини-вывод',
              hint: '2–3 коротких предложения: что главное в теме',
            ),
            const SizedBox(height: 10),
            _NoteInput(
              controller: _unclear,
              label: 'Что я не понял',
              hint: 'Вопрос, который нужно разобрать позже',
            ),
            const SizedBox(height: 10),
            _NoteInput(
              controller: _teacher,
              label: 'Дополнения учителя',
              hint: 'Свободное место для пояснений с урока',
              minLines: 3,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _save,
              icon: Icon(_saved ? Icons.check : Icons.save_outlined),
              label: Text(_saved ? 'Сохранено' : 'Сохранить дополнения'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int minLines;

  const _NoteInput({
    required this.controller,
    required this.label,
    required this.hint,
    this.minLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: 6,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  const _LegendCard();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('!', 'важно'),
      ('?', 'непонятно'),
      ('Д', 'дата'),
      ('Ф', 'формула'),
      ('П', 'правило / понятие'),
      ('О', 'моя ошибка'),
      ('ПВ', 'повторить'),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 9,
          children: [
            for (final item in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MarkerBadge(marker: item.$1),
                  const SizedBox(width: 5),
                  Text(item.$2, style: const TextStyle(fontSize: 11)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BookTab extends StatelessWidget {
  final StudyTextbookPageRange? range;

  const _BookTab({required this.range});

  @override
  Widget build(BuildContext context) {
    final currentRange = range;
    if (currentRange == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Для этого параграфа пока не удалось определить оригинальные страницы.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _BookPager(range: currentRange);
  }
}

class _BookPager extends ConsumerStatefulWidget {
  final StudyTextbookPageRange range;

  const _BookPager({required this.range});

  @override
  ConsumerState<_BookPager> createState() => _BookPagerState();
}

class _BookPagerState extends ConsumerState<_BookPager> {
  int _index = 0;

  int get _count => widget.range.pdfEnd - widget.range.pdfStart + 1;

  @override
  Widget build(BuildContext context) {
    final pdfPage = widget.range.pdfStart + _index;
    final printedPage = widget.range.printedStart + _index;
    final request = (bookId: widget.range.source.bookId, pdfPage: pdfPage);
    final page = ref.watch(studyTextbookPageImageProvider(request));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.range.source.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Страница $printedPage · ${_index + 1}/$_count',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const _LocalImageBadge(),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: page.when(
              loading: () => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Подготовка страницы из официального PDF…'),
                  ],
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.danger,
                        size: 34,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(
                          studyTextbookPageImageProvider(request),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (file) => GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _FullImageScreen(
                      file: file,
                      title: 'Страница $printedPage',
                    ),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _index > 0 ? () => setState(() => _index--) : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Назад'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _index + 1 < _count
                      ? () => setState(() => _index++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Дальше'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocalImageBadge extends StatelessWidget {
  const _LocalImageBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'PNG-КЭШ',
        style: TextStyle(
          color: AppColors.accent,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FullImageScreen extends StatelessWidget {
  final File file;
  final String title;

  const _FullImageScreen({required this.file, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          minScale: .7,
          maxScale: 5,
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _GdzTab extends StatelessWidget {
  final StudySubject? subject;
  final bool available;

  const _GdzTab({required this.subject, required this.available});

  @override
  Widget build(BuildContext context) {
    final currentSubject = subject;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(
                  available ? Icons.photo_library_outlined : Icons.info_outline,
                  color: available ? AppColors.accent : AppColors.textDim,
                  size: 38,
                ),
                const SizedBox(height: 10),
                Text(
                  available ? 'Оригинальные фото решений' : 'ГДЗ не подключено',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  available
                      ? 'Выбери раздел и номер задания. Hermes загружает оригинальную фотографию решения и сохраняет её локально.'
                      : 'Для этого предмета сейчас нет настроенного каталога решений. Конспект и учебник продолжают работать.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (available && currentSubject != null) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReshebaScreen(
                          subjectTitle: currentSubject.title,
                          subjectId: currentSubject.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Открыть решения'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewTab extends StatelessWidget {
  final String paragraphId;
  final StudyNoteTemplate template;
  final SharedPreferences prefs;

  const _ReviewTab({
    required this.paragraphId,
    required this.template,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _RecallCard(questions: template.selfCheck),
        const SizedBox(height: 12),
        _ReviewScheduleCard(paragraphId: paragraphId, prefs: prefs),
        const SizedBox(height: 12),
        _ErrorsCard(paragraphId: paragraphId, prefs: prefs),
        const SizedBox(height: 12),
        const _LearnedCriteriaCard(),
      ],
    );
  }
}

class _RecallCard extends StatefulWidget {
  final List<String> questions;

  const _RecallCard({required this.questions});

  @override
  State<_RecallCard> createState() => _RecallCardState();
}

class _RecallCardState extends State<_RecallCard> {
  late List<bool> _done;

  @override
  void initState() {
    super.initState();
    _done = List<bool>.filled(widget.questions.length, false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Самопроверка без учебника',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Сначала ответь вслух или письменно, только потом открывай учебник.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
            const SizedBox(height: 10),
            if (widget.questions.isEmpty)
              const Text('Сформулируй 3–5 вопросов к теме самостоятельно.')
            else
              for (var i = 0; i < widget.questions.length; i++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _done[i],
                  onChanged: (value) => setState(() => _done[i] = value ?? false),
                  title: Text(
                    widget.questions[i],
                    style: const TextStyle(fontSize: 12.5, height: 1.35),
                  ),
                ),
            if (_done.any((value) => value))
              TextButton.icon(
                onPressed: () => setState(
                  () => _done = List<bool>.filled(widget.questions.length, false),
                ),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Сбросить ответы'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewScheduleCard extends StatefulWidget {
  final String paragraphId;
  final SharedPreferences prefs;

  const _ReviewScheduleCard({
    required this.paragraphId,
    required this.prefs,
  });

  @override
  State<_ReviewScheduleCard> createState() => _ReviewScheduleCardState();
}

class _ReviewScheduleCardState extends State<_ReviewScheduleCard> {
  late StudyReviewData _data;

  @override
  void initState() {
    super.initState();
    _data = StudyNotePersistence.readReview(widget.prefs, widget.paragraphId);
  }

  Future<void> _start() async {
    final data = StudyReviewData(startedAt: DateTime.now());
    await StudyNotePersistence.writeReview(widget.prefs, widget.paragraphId, data);
    if (mounted) setState(() => _data = data);
  }

  Future<void> _completeNext() async {
    if (_data.startedAt == null ||
        _data.completedStages >= StudyNotePersistence.reviewIntervals.length) {
      return;
    }
    final data = StudyReviewData(
      startedAt: _data.startedAt,
      completedStages: _data.completedStages + 1,
    );
    await StudyNotePersistence.writeReview(widget.prefs, widget.paragraphId, data);
    if (mounted) setState(() => _data = data);
  }

  Future<void> _reset() async {
    const data = StudyReviewData();
    await StudyNotePersistence.writeReview(widget.prefs, widget.paragraphId, data);
    if (mounted) setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    final next = StudyNotePersistence.nextReviewAt(_data);
    final complete =
        _data.completedStages >= StudyNotePersistence.reviewIntervals.length;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Интервальное повторение',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Главный принцип — вспоминать материал без подсказки, а не перечитывать его много раз.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (var i = 0;
                i < StudyNotePersistence.reviewIntervals.length;
                i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  i < _data.completedStages
                      ? Icons.check_circle
                      : i == _data.completedStages && _data.startedAt != null
                          ? Icons.schedule
                          : Icons.radio_button_unchecked,
                  color: i < _data.completedStages
                      ? AppColors.accent
                      : AppColors.textDim,
                ),
                title: Text(
                  StudyNotePersistence.stageLabel(i),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            if (_data.startedAt == null)
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Начать график повторений'),
              )
            else if (complete)
              const Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0x1429D391),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Text(
                  'Все 5 этапов пройдены. Проведи контрольную самопроверку.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            else ...[
              if (next != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Следующий этап: ${_dateTime(next)}',
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _completeNext,
                icon: const Icon(Icons.check),
                label: const Text('Этап выполнен'),
              ),
            ],
            if (_data.startedAt != null) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Начать график заново'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorsCard extends StatefulWidget {
  final String paragraphId;
  final SharedPreferences prefs;

  const _ErrorsCard({required this.paragraphId, required this.prefs});

  @override
  State<_ErrorsCard> createState() => _ErrorsCardState();
}

class _ErrorsCardState extends State<_ErrorsCard> {
  late List<String> _errors;

  @override
  void initState() {
    super.initState();
    _errors = List<String>.from(
      StudyNotePersistence.readText(widget.prefs, widget.paragraphId).errors,
    );
  }

  Future<void> _save() async {
    final current = StudyNotePersistence.readText(
      widget.prefs,
      widget.paragraphId,
    );
    await StudyNotePersistence.writeText(
      widget.prefs,
      widget.paragraphId,
      StudyNoteTextData(
        ownExample: current.ownExample,
        conclusion: current.conclusion,
        teacherNotes: current.teacherNotes,
        unclear: current.unclear,
        errors: _errors,
      ),
    );
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить ошибку'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Что сделал неправильно и как правильно?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    setState(() => _errors.add(value));
    await _save();
  }

  Future<void> _remove(int index) async {
    setState(() => _errors.removeAt(index));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Мои ошибки',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Добавить ошибку',
                  onPressed: _add,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (_errors.isEmpty)
              const Text(
                'Пока пусто. Записывай сюда ошибки из задач, правил и самопроверок.',
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              )
            else
              for (var i = 0; i < _errors.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const _MarkerBadge(marker: 'О'),
                  title: Text(
                    _errors[i],
                    style: const TextStyle(fontSize: 12.5, height: 1.35),
                  ),
                  trailing: IconButton(
                    tooltip: 'Удалить',
                    onPressed: () => _remove(i),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LearnedCriteriaCard extends StatelessWidget {
  const _LearnedCriteriaCard();

  @override
  Widget build(BuildContext context) {
    const criteria = [
      'Объяснить тему без учебника.',
      'Привести собственный пример.',
      'Решить типовое задание или выполнить практику.',
      'Ответить на вопросы самопроверки.',
      'Связать новую тему с предыдущей.',
      'Обнаружить и исправить свою ошибку.',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Когда тема считается выученной',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final item in criteria)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 17,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _dateOnly(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month.${date.year}';
}

String _dateTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_dateOnly(date)} · $hour:$minute';
}
