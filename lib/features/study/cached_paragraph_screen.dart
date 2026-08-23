// Экран параграфа с устойчивым отображением оригинальных страниц учебника.
//
// PDF используется только как первоисточник. Нужные страницы один раз
// рендерятся в PNG и дальше показываются из локального кэша, поэтому формулы,
// таблицы и рисунки не зависят от повторного live-рендера PDF-виджета.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/study/local_study_content.dart';
import '../../services/study/resheba_service.dart';
import '../../services/study/study_content_quality.dart';
import '../../services/study/study_service.dart';
import '../../services/study/study_textbook_catalog.dart';
import '../../services/study/study_textbook_page_image_service.dart';
import 'resheba_screen.dart';

class CachedParagraphScreen extends ConsumerWidget {
  final String paragraphId;
  final StudyParagraph? initial;

  const CachedParagraphScreen({
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
    final sourceReport = StudyContentQuality.inspect(paragraph.sourceText);
    final local = LocalStudyContent.build(
      paragraph.sourceText,
      analysis: subject?.analysis ?? 'humanities',
    );
    final exactScience = subject?.analysis == 'exact';
    final hasSolutionPhotos = subject != null &&
        ReshebaService.jsPathFor(subject.title) != null;
    final textbookRange = StudyTextbookCatalog.rangeFor(
      chapter: paragraph.chapter,
      pages: paragraph.pages,
      subjectTitle: subject?.title,
      siblings: state.paragraphs
          .where((item) => item.subjectId == paragraph.subjectId)
          .map((item) => (chapter: item.chapter, pages: item.pages)),
    );
    final visibleChapter =
        StudyTextbookCatalog.visibleChapter(paragraph.chapter);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          paragraph.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Выучено',
            onPressed: () => notifier.toggleLearned(paragraph.id),
            icon: Icon(
              paragraph.learned
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
              color: paragraph.learned ? AppColors.accent : null,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) =>
                _onMenu(context, ref, value, paragraph),
            itemBuilder: (_) => [
              if (paragraph.content.trim().isNotEmpty)
                const PopupMenuItem(
                  value: 'clear_legacy',
                  child: Text('Удалить старый конспект'),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Удалить параграф'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            paragraph.title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            [
              if (subject != null) subject.title,
              if (subject != null && subject.subtitle.isNotEmpty)
                subject.subtitle,
              if (visibleChapter.isNotEmpty) visibleChapter,
              if (paragraph.pages.isNotEmpty) paragraph.pages,
            ].join(' · '),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const _StableOriginalBanner(),
          if (textbookRange != null) ...[
            const SizedBox(height: 12),
            _CachedTextbookPagesCard(range: textbookRange),
          ] else ...[
            const SizedBox(height: 12),
            const _NoTextbookPageCard(),
          ],
          if (hasSolutionPhotos && subject != null) ...[
            const SizedBox(height: 12),
            _SolutionPhotosCard(subject: subject),
          ],
          const SizedBox(height: 12),
          _SourceQualityCard(report: sourceReport, pages: paragraph.pages),
          const SizedBox(height: 16),
          if (exactScience)
            const _ExactScienceNotice()
          else ...[
            Text(
              subject?.analysis == 'languages'
                  ? 'Правила и упражнения'
                  : 'Конспект параграфа',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Текст ниже используется для поиска и конспекта. Формулы, '
              'таблицы и рисунки сверяй с оригинальной страницей выше.',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            if (local.isEmpty)
              const _MissingSourceCard()
            else
              for (final section in local.sections) ...[
                _LocalSectionCard(section: section),
                const SizedBox(height: 10),
              ],
          ],
          if (paragraph.content.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(
                  Icons.history_edu_outlined,
                  color: AppColors.violet,
                ),
                title: const Text(
                  'Сохранённый прежний конспект',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Сохранён для совместимости и по умолчанию скрыт',
                  style: TextStyle(fontSize: 11),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: MarkdownBody(
                      data: paragraph.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context),
                      ).copyWith(
                        p: const TextStyle(fontSize: 13, height: 1.5),
                        listBullet:
                            const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
    StudyParagraph paragraph,
  ) async {
    final notifier = ref.read(studyProvider.notifier);
    if (value == 'clear_legacy') {
      await notifier.clearParagraphContent(paragraph.id);
      return;
    }
    if (value != 'delete') return;

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
    await notifier.removeParagraph(paragraph.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _StableOriginalBanner extends StatelessWidget {
  const _StableOriginalBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: .35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.image_outlined, color: AppColors.accent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Оригинальная страница рендерится один раз и сохраняется как '
              'изображение высокой чёткости. Повторно открывается уже из кэша.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CachedTextbookPagesCard extends ConsumerWidget {
  final StudyTextbookPageRange range;

  const _CachedTextbookPagesCard({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = (
      bookId: range.source.bookId,
      pdfPage: range.pdfStart,
    );
    final page = ref.watch(studyTextbookPageImageProvider(request));

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.menu_book_rounded, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Оригинальная страница учебника',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${range.source.title} · ${range.printedLabel}',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const _CachedBadge(),
              ],
            ),
            const SizedBox(height: 12),
            page.when(
              loading: () => const _PagePreparing(),
              error: (error, _) => _PageError(
                message: error.toString(),
                onRetry: () =>
                    ref.invalidate(studyTextbookPageImageProvider(request)),
              ),
              data: (file) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _CachedTextbookViewerScreen(
                            range: range,
                          ),
                        ),
                      ),
                      child: SizedBox(
                        height: 420,
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _CachedTextbookViewerScreen(
                          range: range,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.fullscreen_rounded),
                    label: Text(
                      range.printedStart == range.printedEnd
                          ? 'Открыть страницу полностью'
                          : 'Открыть все страницы параграфа',
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'После первого рендера эта страница работает без интернета.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 10.5,
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

class _CachedBadge extends StatelessWidget {
  const _CachedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: .35)),
      ),
      child: const Text(
        'PNG-КЭШ',
        style: TextStyle(
          color: AppColors.accent,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class _PagePreparing extends StatelessWidget {
  const _PagePreparing();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(),
        SizedBox(height: 10),
        Text(
          'Hermes загружает официальный PDF и готовит изображение страницы. '
          'Это выполняется один раз.',
          style: TextStyle(
            color: AppColors.textDim,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _PageError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _PageError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.danger.withValues(alpha: .30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(fontSize: 11.5, height: 1.4)),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Подготовить заново'),
          ),
        ],
      ),
    );
  }
}

class _CachedTextbookViewerScreen extends ConsumerWidget {
  final StudyTextbookPageRange range;

  const _CachedTextbookViewerScreen({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = range.pdfEnd - range.pdfStart + 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(range.printedLabel),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: count,
        itemBuilder: (context, index) {
          final pdfPage = range.pdfStart + index;
          final printedPage = range.printedStart + index;
          final request = (bookId: range.source.bookId, pdfPage: pdfPage);
          final image = ref.watch(studyTextbookPageImageProvider(request));
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: Column(
              children: [
                Text(
                  'Страница $printedPage',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                image.when(
                  loading: () => const SizedBox(
                    height: 320,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    color: AppColors.surface,
                    child: Column(
                      children: [
                        Text(
                          error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => ref.invalidate(
                            studyTextbookPageImageProvider(request),
                          ),
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                  data: (file) => InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Container(
                      color: Colors.white,
                      alignment: Alignment.center,
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NoTextbookPageCard extends StatelessWidget {
  const _NoTextbookPageCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.warning),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Для этого параграфа пока не удалось определить оригинальную '
                'страницу. Hermes не будет показывать случайную страницу.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SolutionPhotosCard extends StatelessWidget {
  final StudySubject subject;

  const _SolutionPhotosCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReshebaScreen(
              subjectTitle: subject.title,
              subjectId: subject.id,
            ),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined, color: AppColors.accent),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Фото решений ГДЗ',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Оригинальные изображения решений без OCR. Открытые '
                      'номера сохраняются на телефоне.',
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExactScienceNotice extends StatelessWidget {
  const _ExactScienceNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: .45)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.functions, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Для точных предметов повреждённый текст формул не используется '
              'как источник. Основной материал — оригинальная страница выше.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalSectionCard extends StatelessWidget {
  final LocalStudySection section;

  const _LocalSectionCard({required this.section});

  IconData get icon {
    switch (section.type) {
      case LocalStudySectionType.overview:
        return Icons.subject;
      case LocalStudySectionType.keyPoints:
        return Icons.format_list_bulleted_rounded;
      case LocalStudySectionType.terms:
        return Icons.translate_rounded;
      case LocalStudySectionType.rules:
        return Icons.rule;
      case LocalStudySectionType.examples:
        return Icons.lightbulb_outline;
      case LocalStudySectionType.tasks:
        return Icons.calculate_outlined;
      case LocalStudySectionType.questions:
        return Icons.question_answer_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: section.type == LocalStudySectionType.overview,
        leading: Icon(icon, color: AppColors.accent),
        title: Text(
          section.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        children: [
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  item,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MissingSourceCard extends StatelessWidget {
  const _MissingSourceCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Текстовый слой этого параграфа повреждён или отсутствует. '
          'Оригинальная страница выше остаётся основным источником.',
          style: TextStyle(height: 1.4),
        ),
      ),
    );
  }
}

class _SourceQualityCard extends StatelessWidget {
  final StudySourceReport report;
  final String pages;

  const _SourceQualityCard({required this.report, required this.pages});

  @override
  Widget build(BuildContext context) {
    final warning = report.quality != StudySourceQuality.ready;
    final color = warning ? AppColors.warning : AppColors.accent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              warning ? Icons.warning_amber_rounded : Icons.verified_outlined,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  report.label,
                  if (pages.isNotEmpty) pages,
                  '${report.characterCount} символов',
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
