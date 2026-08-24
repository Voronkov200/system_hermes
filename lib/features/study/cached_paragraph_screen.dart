// Экран параграфа с устойчивым отображением оригинальных страниц учебника.
// PDF используется только как первоисточник: нужная страница один раз
// рендерится в PNG и затем открывается из локального кэша.

import 'package:flutter/material.dart';
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
    final local = LocalStudyContent.build(
      paragraph.sourceText,
      analysis: subject?.analysis ?? 'humanities',
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
    final visibleChapter =
        StudyTextbookCatalog.visibleChapter(paragraph.chapter);
    final exact = subject?.analysis == 'exact';

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
          IconButton(
            tooltip: 'Удалить параграф',
            onPressed: () => _delete(context, ref, paragraph),
            icon: const Icon(Icons.delete_outline),
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
          const _OriginalPageBanner(),
          const SizedBox(height: 12),
          if (range != null)
            _CachedTextbookCard(range: range)
          else
            const _NoPageCard(),
          if (subject != null &&
              ReshebaService.jsPathFor(subject.title) != null) ...[
            const SizedBox(height: 12),
            _SolutionCard(subject: subject),
          ],
          const SizedBox(height: 12),
          _QualityCard(report: quality, pages: paragraph.pages),
          const SizedBox(height: 16),
          if (exact)
            const _ExactNotice()
          else if (local.isEmpty)
            const _MissingTextCard()
          else ...[
            const Text(
              'Локальный конспект',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Текст используется для поиска и конспекта. Формулы, таблицы '
              'и рисунки берутся с оригинальной страницы выше.',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            for (final section in local.sections) ...[
              _TextSection(section: section),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 24),
        ],
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

class _OriginalPageBanner extends StatelessWidget {
  const _OriginalPageBanner();

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
              'Страница учебника один раз рендерится в PNG высокой чёткости '
              'и затем открывается из локального кэша.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CachedTextbookCard extends ConsumerWidget {
  final StudyTextbookPageRange range;

  const _CachedTextbookCard({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = (bookId: range.source.bookId, pdfPage: range.pdfStart);
    final page = ref.watch(studyTextbookPageImageProvider(request));

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${range.source.title} · ${range.printedLabel}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            page.when(
              loading: () => const _PreparingPage(),
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
                      onTap: () => _openViewer(context),
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
                    onPressed: () => _openViewer(context),
                    icon: const Icon(Icons.fullscreen_rounded),
                    label: Text(
                      range.printedStart == range.printedEnd
                          ? 'Открыть страницу полностью'
                          : 'Открыть все страницы параграфа',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'После первого рендера страница доступна без интернета.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textDim, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openViewer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CachedTextbookViewer(range: range),
      ),
    );
  }
}

class _PreparingPage extends StatelessWidget {
  const _PreparingPage();

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
          style: TextStyle(color: AppColors.textDim, fontSize: 11.5, height: 1.4),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: const TextStyle(color: AppColors.danger)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Подготовить заново'),
        ),
      ],
    );
  }
}

class _CachedTextbookViewer extends ConsumerWidget {
  final StudyTextbookPageRange range;

  const _CachedTextbookViewer({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = range.pdfEnd - range.pdfStart + 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(range.printedLabel)),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: count,
        itemBuilder: (context, index) {
          final pdfPage = range.pdfStart + index;
          final printedPage = range.printedStart + index;
          final request = (bookId: range.source.bookId, pdfPage: pdfPage);
          final page = ref.watch(studyTextbookPageImageProvider(request));
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: Column(
              children: [
                Text(
                  'Страница $printedPage',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                page.when(
                  loading: () => const SizedBox(
                    height: 320,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => _PageError(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(
                      studyTextbookPageImageProvider(request),
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

class _SolutionCard extends StatelessWidget {
  final StudySubject subject;

  const _SolutionCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(
          Icons.photo_library_outlined,
          color: AppColors.accent,
        ),
        title: const Text(
          'Фото решений ГДЗ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Оригинальные изображения без OCR'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReshebaScreen(
              subjectTitle: subject.title,
              subjectId: subject.id,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoPageCard extends StatelessWidget {
  const _NoPageCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: AppColors.warning),
            SizedBox(width: 10),
            Expanded(
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

class _ExactNotice extends StatelessWidget {
  const _ExactNotice();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'Для точных предметов повреждённый текст формул не используется как '
          'источник. Основной материал — оригинальная страница выше.',
          style: TextStyle(fontSize: 12, height: 1.45),
        ),
      ),
    );
  }
}

class _MissingTextCard extends StatelessWidget {
  const _MissingTextCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'Текстовый слой этого параграфа повреждён или отсутствует. '
          'Оригинальная страница выше остаётся основным источником.',
          style: TextStyle(height: 1.4),
        ),
      ),
    );
  }
}

class _TextSection extends StatelessWidget {
  final LocalStudySection section;

  const _TextSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: section.type == LocalStudySectionType.overview,
        leading: const Icon(Icons.notes_rounded, color: AppColors.accent),
        title: Text(
          section.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        children: [
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SelectableText(
                item,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  final StudySourceReport report;
  final String pages;

  const _QualityCard({required this.report, required this.pages});

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
