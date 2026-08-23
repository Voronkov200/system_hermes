// Экран параграфа: полностью локальный разбор вложенного текста учебника.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/study/local_study_content.dart';
import '../../services/study/resheba_service.dart';
import '../../services/study/study_content_quality.dart';
import '../../services/study/study_service.dart';
import 'resheba_screen.dart';

class ParagraphScreen extends ConsumerWidget {
  final String paragraphId;
  final StudyParagraph? initial;

  const ParagraphScreen({
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
            icon: Icon(
              paragraph.learned
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
              color: paragraph.learned ? AppColors.accent : null,
            ),
            onPressed: () => notifier.toggleLearned(paragraph.id),
          ),
          PopupMenuButton<String>(
            onSelected: (value) =>
                _onMenu(context, ref, value, paragraph),
            itemBuilder: (_) => [
              if (!exactScience && paragraph.content.trim().isNotEmpty)
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
          if (subject != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                [
                  subject.title,
                  if (subject.subtitle.isNotEmpty) subject.subtitle,
                  if (paragraph.chapter.isNotEmpty) paragraph.chapter,
                  if (paragraph.pages.isNotEmpty) paragraph.pages,
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (exactScience) ...[
            const _ExactScienceNotice(),
            if (hasSolutionPhotos) ...[
              const SizedBox(height: 12),
              _SolutionPhotosCard(
                subject: subject,
              ),
            ],
            const SizedBox(height: 12),
            _SourceQualityCard(report: sourceReport, pages: paragraph.pages),
          ] else ...[
            _OfflineNotice(sectionCount: local.sections.length),
            const SizedBox(height: 12),
            _SourceQualityCard(report: sourceReport, pages: paragraph.pages),
            const SizedBox(height: 18),
            const Text(
              'Локальный разбор',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Все блоки ниже извлечены из текста учебника на телефоне. '
              'Hermes не отправляет параграф в ИИ и не дописывает факты.',
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
          if (!exactScience && paragraph.content.trim().isNotEmpty) ...[
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
          if (!exactScience) ...[
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(Icons.menu_book, color: AppColors.cyan),
                title: const Text(
                  'Исходный текст учебника',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  local.isEmpty
                      ? 'Текст отсутствует'
                      : '${local.sourceText.length} символов · локально',
                  style: const TextStyle(fontSize: 11),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: SelectableText(
                      local.isEmpty
                          ? 'Исходный текст отсутствует.'
                          : local.sourceText,
                      style: const TextStyle(fontSize: 12, height: 1.48),
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
              'Повреждённый OCR для точных предметов больше не показывается: '
              'он ломал степени, корни, дроби и знаки. Открывай фотографию '
              'решения — на ней формулы остаются в исходном виде.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ],
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
                      'Открыть фото решений',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Выбери раздел и номер. Фото загружается без OCR и '
                      'сохраняется на телефоне для повторного просмотра.',
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

class _OfflineNotice extends StatelessWidget {
  final int sectionCount;

  const _OfflineNotice({required this.sectionCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: .36)),
      ),
      child: Row(
        children: [
          const Icon(Icons.offline_bolt, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Готово без интернета · найдено разделов: $sectionCount',
              style: const TextStyle(fontWeight: FontWeight.w700),
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

  Color get color {
    switch (section.type) {
      case LocalStudySectionType.overview:
        return AppColors.cyan;
      case LocalStudySectionType.rules:
        return AppColors.violet;
      case LocalStudySectionType.examples:
        return AppColors.warning;
      case LocalStudySectionType.tasks:
        return AppColors.accent;
      case LocalStudySectionType.questions:
        return AppColors.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: section.type == LocalStudySectionType.overview,
        leading: Icon(icon, color: color),
        title: Text(
          section.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${section.items.length} '
          '${section.items.length == 1 ? 'фрагмент' : 'фрагментов'}',
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          for (var i = 0; i < section.items.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: .20)),
                ),
                child: SelectableText(
                  section.items[i],
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: AppColors.danger),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Не удалось распознать текст этого параграфа. Локальный '
                'разбор не создаёт пустой или выдуманный конспект.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ],
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning ? Icons.warning_amber_rounded : Icons.verified_outlined,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (pages.isNotEmpty) pages,
                      '${report.characterCount} символов',
                      if (report.quality == StudySourceQuality.noisy)
                        'формулы нужно сверять с PDF',
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11,
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
