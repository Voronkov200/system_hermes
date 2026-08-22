// Экран параграфа «Учёба»: конспект, разбор правил/задач/вопросов.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/study/study_content_quality.dart';
import '../../services/study/study_service.dart';

class ParagraphScreen extends ConsumerStatefulWidget {
  final String paragraphId;
  final StudyParagraph? initial;

  const ParagraphScreen({
    super.key,
    required this.paragraphId,
    this.initial,
  });

  @override
  ConsumerState<ParagraphScreen> createState() => _ParagraphScreenState();
}

class _ParagraphScreenState extends ConsumerState<ParagraphScreen> {
  StudyParagraph? _find(List<StudyParagraph> all) {
    for (final x in all) {
      if (x.id == widget.paragraphId) return x;
    }
    return widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(studyProvider);
    final notifier = ref.read(studyProvider.notifier);
    final p = _find(st.paragraphs);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Параграф')),
        body: const Center(child: Text('Параграф не найден')),
      );
    }
    final busy = st.workingId == p.id && st.busy;
    final subject = notifier.subjectOf(p.subjectId);
    final sourceReport = StudyContentQuality.inspect(p.sourceText);
    final canAnalyze = sourceReport.canAnalyze;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          p.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Выучено',
            icon: Icon(
              p.learned ? Icons.check_circle : Icons.check_circle_outline,
              color: p.learned ? AppColors.accent : null,
            ),
            onPressed: () => notifier.toggleLearned(p.id),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(v, p),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('Очистить конспект'),
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
            p.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subject != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  subject.title,
                  if (subject.subtitle.isNotEmpty) subject.subtitle,
                  if (p.chapter.isNotEmpty) p.chapter,
                  if (p.pages.isNotEmpty) p.pages,
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 12),
          _SourceQualityCard(report: sourceReport, pages: p.pages),
          const SizedBox(height: 12),
          if (busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
            const Text(
              'ИИ разбирает параграф…',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
          if (st.error != null && st.workingId == p.id)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                st.error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Конспект Hermes',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (p.content.trim().isEmpty)
                    Text(
                      canAnalyze
                          ? 'Конспект ещё не создан. Выбери режим разбора ниже.'
                          : 'Разбор заблокирован, пока нет пригодного текста '
                              'учебника.',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 13,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: p.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context),
                      ).copyWith(
                        p: const TextStyle(fontSize: 13, height: 1.5),
                        listBullet: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Разбор параграфа',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ModeChip(
                icon: Icons.notes,
                label: 'Создать конспект',
                onTap: busy || !canAnalyze
                    ? null
                    : () => _analyze(p, StudyController.modeConspectus),
              ),
              _ModeChip(
                icon: Icons.rule,
                label: 'Правила и теоремы',
                onTap: busy || !canAnalyze
                    ? null
                    : () => _analyze(p, StudyController.modeRules),
              ),
              _ModeChip(
                icon: Icons.calculate,
                label: 'Задания с решением',
                onTap: busy || !canAnalyze
                    ? null
                    : () => _analyze(p, StudyController.modeTasks),
              ),
              _ModeChip(
                icon: Icons.question_answer,
                label: 'Вопросы после параграфа',
                onTap: busy || !canAnalyze
                    ? null
                    : () => _analyze(p, StudyController.modeAnswers),
              ),
              if (subject?.analysis == 'literature')
                _ModeChip(
                  icon: Icons.auto_stories,
                  label: 'Краткое содержание',
                  onTap: busy || !canAnalyze
                      ? null
                      : () => _analyze(p, StudyController.modeSummary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.menu_book, color: AppColors.cyan),
              title: const Text(
                'Исходный текст учебника',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Для сверки конспекта и формул',
                style: TextStyle(fontSize: 11),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: SelectableText(
                    p.sourceText.trim().isEmpty
                        ? 'Исходный текст отсутствует.'
                        : StudyContentQuality.preview(p.sourceText),
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _analyze(StudyParagraph paragraph, String mode) async {
    try {
      await ref.read(studyProvider.notifier).analyzeParagraph(
            paragraph,
            mode: mode,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Разбор не выполнен: $error')),
      );
    }
  }

  Future<void> _onMenu(String v, StudyParagraph p) async {
    final notifier = ref.read(studyProvider.notifier);
    switch (v) {
      case 'clear':
        await notifier.clearParagraphContent(p.id);
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text('Удалить параграф «${p.title}»?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        );
        if (ok == true && mounted) {
          await notifier.removeParagraph(p.id);
          if (mounted) Navigator.of(context).pop();
        }
    }
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
                        'нечёткие формулы нельзя восстанавливать по догадке',
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

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ModeChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: AppColors.cyan),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor: AppColors.surfaceAlt,
      side: BorderSide.none,
    );
  }
}
