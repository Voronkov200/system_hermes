// Просмотр и редактирование заметки Obsidian.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/obsidian_service.dart';

class NoteScreen extends ConsumerStatefulWidget {
  final String notePath;

  const NoteScreen({super.key, required this.notePath});

  @override
  ConsumerState<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends ConsumerState<NoteScreen> {
  ObsidianNote? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final note = await ref.read(obsidianProvider.notifier).readNote(widget.notePath);
    if (mounted) setState(() => _note = note);
  }

  Future<void> _edit() async {
    final controller = TextEditingController(text: _note?.content ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Редактировать заметку'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Markdown'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final error = await ref
        .read(obsidianProvider.notifier)
        .editNote(widget.notePath, controller.text);
    if (error != null) {
      if (mounted) toast(context, error);
    } else {
      await _load();
      if (mounted) toast(context, 'Сохранено');
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return Scaffold(
      appBar: AppBar(
        title: Text(note?.title ?? 'Заметка'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: note == null ? null : _edit,
          ),
        ],
      ),
      body: note == null
          ? const Center(
              child: Text('Не удалось прочитать заметку',
                  style: TextStyle(color: AppColors.textDim)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: note.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Изменено: ${fmtDateTime(note.modifiedAt)}',
                      style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
                ],
              ),
            ),
    );
  }
}
