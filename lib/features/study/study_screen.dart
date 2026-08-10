// Экран «Учёба»: предметы 11 класса и дополнительная литература.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/study/study_service.dart';

/// Маппинг ключей иконок каталога на Material-иконки.
IconData studyIcon(String key) => switch (key) {
      'history' => Icons.account_balance,
      'world' => Icons.public,
      'society' => Icons.groups,
      'lang_bel' => Icons.translate,
      'lit_bel' => Icons.auto_stories,
      'lang_ru' => Icons.translate,
      'lit_ru' => Icons.menu_book,
      'lang_en' => Icons.language,
      'algebra' => Icons.functions,
      'geometry' => Icons.square_foot,
      'physics' => Icons.science,
      'chemistry' => Icons.biotech,
      'biology' => Icons.eco,
      'geo' => Icons.map,
      'informatics' => Icons.computer,
      'astronomy' => Icons.rocket_launch,
      _ => Icons.book,
    };

class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(studyProvider);
    final subjects = st.subjects.where((s) => s.kind == 'subject').toList();
    final guides = st.subjects.where((s) => s.kind == 'guide').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Учёба')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addManualSubject(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Предмет'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (subjects.isNotEmpty) ...[
            _Header('Предметы 11 класса'),
            const SizedBox(height: 8),
            for (final s in subjects) ...[
              _SubjectCard(subject: s),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 8),
          _Header('Дополнительная литература'),
          const SizedBox(height: 8),
          for (final g in guides) ...[
            _SubjectCard(subject: g),
            const SizedBox(height: 10),
          ],
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _addGuide(context, ref),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.library_add, color: AppColors.warning),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Добавить пособие / справочник / сборник',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textDim),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _addManualSubject(BuildContext context, WidgetRef ref) async {
    final title = await _askTitle(context, 'Название предмета');
    if (title == null || title.trim().isEmpty) return;
    try {
      await ref
          .read(studyProvider.notifier)
          .addSubject(title: title.trim(), category: 'Своё');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _addGuide(BuildContext context, WidgetRef ref) async {
    final title = await _askTitle(context, 'Название пособия');
    if (title == null || title.trim().isEmpty) return;
    try {
      await ref.read(studyProvider.notifier).addSubject(
            title: title.trim(),
            kind: 'guide',
            icon: 'guide',
            category: 'Дополнительная литература',
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<String?> _askTitle(BuildContext context, String label) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Введите название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    return result;
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
}

class _SubjectCard extends ConsumerWidget {
  final StudySubject subject;
  const _SubjectCard({required this.subject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(studyProvider);
    final count = st.paragraphs
        .where((p) => p.subjectId == subject.id)
        .length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          '/study_subject/${subject.id}',
          extra: subject,
        ),
        onLongPress: () => _menu(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  studyIcon(subject.icon),
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subject.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subject.subtitle,
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (count > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$count параграф${_plural(count)}',
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (subject.filePath != null)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.picture_as_pdf, size: 18, color: AppColors.danger),
                ),
              const Icon(Icons.chevron_right, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final s = subject;
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(s.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              dense: true,
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Прикрепить PDF-учебник'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Переименовать'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Удалить предмет',
                  style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (act == null || !context.mounted) return;
    switch (act) {
      case 'pdf':
        await _attachPdf(context, ref, s);
        break;
      case 'rename':
        await _rename(context, ref, s);
        break;
      case 'delete':
        final ok = await _confirm(context, 'Удалить «${s.title}»?');
        if (ok == true && context.mounted) {
          await ref.read(studyProvider.notifier).removeSubject(s.id);
        }
    }
  }

  Future<void> _attachPdf(
      BuildContext context, WidgetRef ref, StudySubject s) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = res?.files.single.path;
    if (path == null || !context.mounted) return;
    try {
      await ref.read(studyProvider.notifier).attachPdf(s, path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF прикреплён — теперь «Разобрать учебник»')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, StudySubject s) async {
    final ctrl = TextEditingController(text: s.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty || !context.mounted) return;
    await ref
        .read(studyProvider.notifier)
        .updateSubject(s.copyWith(title: title.trim()));
  }

  Future<bool?> _confirm(BuildContext context, String text) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
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

  static String _plural(int n) {
    final m = n % 10;
    final h = n % 100;
    if (m == 1 && h != 11) return '';
    if (m >= 2 && m <= 4 && (h < 12 || h > 14)) return 'а';
    return 'ов';
  }
}
