// Экран предмета «Учёба»: параграфы, разбор PDF, генерация конспектов.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/study/study_service.dart';

class SubjectScreen extends ConsumerStatefulWidget {
  final String subjectId;
  final StudySubject? initial;

  const SubjectScreen({super.key, required this.subjectId, this.initial});

  @override
  ConsumerState<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends ConsumerState<SubjectScreen> {
  @override
  Widget build(BuildContext context) {
    final st = ref.watch(studyProvider);
    final subject = ref
        .read(studyProvider.notifier)
        .subjectOf(widget.subjectId) ??
        widget.initial;
    if (subject == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Учёба')),
        body: const Center(child: Text('Предмет не найден')),
      );
    }
    final paragraphs = st.paragraphs
        .where((p) => p.subjectId == subject.id)
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    return Scaffold(
      appBar: AppBar(
        title: Text(subject.title),
        actions: [
          IconButton(
            tooltip: 'Меню',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _menu(subject),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (subject.filePath != null) ...[
            _PdfBanner(subject: subject, onParse: () => _parsePdf(subject)),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: st.busy ? null : () => _addParagraph(subject),
                  icon: const Icon(Icons.add),
                  label: Text(
                    subject.analysis == 'literature'
                        ? 'Добавить произведение'
                        : 'Параграф вручную',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (st.workingId != null && st.busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (paragraphs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  'Параграфов ещё нет.\nПрикрепи PDF-учебник и нажми '
                  '«Разобрать учебник»\nили добавь параграф вручную.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
              ),
            )
          else
            for (final p in paragraphs) ...[
              _ParagraphTile(paragraph: p),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _parsePdf(StudySubject subject) async {
    final notifier = ref.read(studyProvider.notifier);
    setState(() {});
    try {
      final count = await notifier.reparsePdf(subject);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Учебник разобран: $count параграф${_pl(count)}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка разбора: $e')),
        );
      }
    }
  }

  static String _pl(int n) {
    if (n % 10 == 1 && n % 100 != 11) return '';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)) {
      return 'а';
    }
    return 'ов';
  }

  Future<void> _addParagraph(StudySubject subject) async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый параграф'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Например: § 7. Становление государства',
          ),
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
    if (title == null || title.trim().isEmpty || !mounted) return;
    await ref.read(studyProvider.notifier).addParagraph(
          subject,
          title: title.trim(),
        );
  }

  Future<void> _menu(StudySubject subject) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(subject.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              dense: true,
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(subject.filePath == null
                  ? 'Прикрепить PDF-учебник'
                  : 'Заменить PDF-учебник'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.library_books),
              title: const Text('Разобрать учебник на параграфы'),
              subtitle: const Text('PDF → параграфы (создаст заново)'),
              onTap: () => Navigator.pop(ctx, 'parse'),
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
    if (act == null || !mounted) return;
    switch (act) {
      case 'pdf':
        await _attachPdf(subject);
        break;
      case 'parse':
        await _parsePdf(subject);
        break;
      case 'rename':
        await _rename(subject);
        break;
      case 'delete':
        await _delete(subject);
        break;
    }
  }

  Future<void> _attachPdf(StudySubject subject) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    try {
      await ref.read(studyProvider.notifier).attachPdf(subject, path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF прикреплён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _rename(StudySubject subject) async {
    final ctrl = TextEditingController(text: subject.title);
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
    if (title == null || title.trim().isEmpty || !mounted) return;
    await ref
        .read(studyProvider.notifier)
        .updateSubject(subject.copyWith(title: title.trim()));
  }

  Future<void> _delete(StudySubject subject) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('Удалить «${subject.title}» со всеми параграфами?'),
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
      await ref.read(studyProvider.notifier).removeSubject(subject.id);
      if (mounted) context.pop();
    }
  }
}

class _PdfBanner extends ConsumerWidget {
  final StudySubject subject;
  final VoidCallback onParse;
  const _PdfBanner({required this.subject, required this.onParse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(studyProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf, color: AppColors.danger),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'PDF-учебник прикреплён',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: st.busy ? null : onParse,
              child: const Text('Разобрать учебник'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParagraphTile extends ConsumerWidget {
  final StudyParagraph paragraph;
  const _ParagraphTile({required this.paragraph});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(studyProvider);
    final busy = st.workingId == paragraph.id && st.busy;
    final p = paragraph;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          '/study_paragraph/${p.id}',
          extra: p,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Checkbox(
                value: p.learned,
                onChanged: (_) =>
                    ref.read(studyProvider.notifier).toggleLearned(p.id),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: p.learned
                            ? TextDecoration.lineThrough
                            : null,
                        color: p.learned ? AppColors.textDim : null,
                      ),
                    ),
                    if (p.pages.isNotEmpty || p.chapter.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (p.chapter.isNotEmpty) p.chapter,
                          if (p.pages.isNotEmpty) p.pages,
                        ].join(' · '),
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (p.content.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          p.content.replaceAll(RegExp(r'[#*_`>\[\]]'), ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
