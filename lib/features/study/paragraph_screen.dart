// Экран параграфа «Учёба»: конспект, разбор правил/задач/вопросов.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
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
  @override
  Widget build(BuildContext context) {
    final st = ref.watch(studyProvider);
    final notifier = ref.read(studyProvider.notifier);
    StudyParagraph? p;
    for (final x in st.paragraphs) {
      if (x.id == widget.paragraphId) {
        p = x;
        break;
      }
    }
    p ??= widget.initial;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Параграф')),
        body: const Center(child: Text('Параграф не найден')),
      );
    }
    final busy = st.workingId == p.id && st.busy;
    final subject = notifier.subjectOf(p.subjectId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Параграф'),
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
              child: p.content.trim().isEmpty
                  ? const Text(
                      'Конспект ещё не создан. Выбери режим разбора ниже:',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13),
                    )
                  : SelectableText(
                      p.content,
                      style: const TextStyle(fontSize: 13, height: 1.5),
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
                label: 'Конспект',
                onTap: busy
                    ? null
                    : () => notifier.analyzeParagraph(
                          p,
                          mode: StudyController.modeConspectus,
                        ),
              ),
              _ModeChip(
                icon: Icons.rule,
                label: 'Правила и теоремы',
                onTap: busy
                    ? null
                    : () => notifier.analyzeParagraph(
                          p,
                          mode: StudyController.modeRules,
                        ),
              ),
              _ModeChip(
                icon: Icons.calculate,
                label: 'Задания с решением',
                onTap: busy
                    ? null
                    : () => notifier.analyzeParagraph(
                          p,
                          mode: StudyController.modeTasks,
                        ),
              ),
              _ModeChip(
                icon: Icons.question_answer,
                label: 'Вопросы после параграфа',
                onTap: busy
                    ? null
                    : () => notifier.analyzeParagraph(
                          p,
                          mode: StudyController.modeAnswers,
                        ),
              ),
              if (subject?.analysis == 'literature')
                _ModeChip(
                  icon: Icons.auto_stories,
                  label: 'Краткое содержание',
                  onTap: busy
                      ? null
                      : () => notifier.analyzeParagraph(
                            p,
                            mode: StudyController.modeSummary,
                          ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
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
