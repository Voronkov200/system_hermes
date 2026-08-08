// Экран "Документы" (в стиле NotebookLM): источники знаний,
// конспекты по параграфам, вопросы по документам.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/agent/file_tools.dart';
import '../../services/obsidian_service.dart';
import '../../services/plan/docs_service.dart';

class DocsScreen extends ConsumerStatefulWidget {
  const DocsScreen({super.key});

  @override
  ConsumerState<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends ConsumerState<DocsScreen> {
  bool _busy = false;
  String _busyLabel = '';

  void _setBusy(bool busy, [String label = '']) {
    if (!mounted) return;
    setState(() {
      _busy = busy;
      _busyLabel = label;
    });
  }

  // ------------------------------------------------------------ добавление

  Future<void> _addPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final src = File(result.files.single.path!);
    if (!await src.exists()) return;

    _setBusy(true, 'Читаю PDF…');
    try {
      final root = await FileTools.root();
      final dir = Directory('${root.path}/docs');
      await dir.create(recursive: true);
      final copy = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.pdf');
      await src.copy(copy.path);
      final text = await ref.read(docsProvider.notifier).extractPdfText(copy.path);
      final title = result.files.single.name.replaceAll(RegExp(r'\.pdf$'), '');
      await ref
          .read(docsProvider.notifier)
          .add(title: title, sourceType: 'pdf', content: text, filePath: copy.path);
      _setBusy(false);
      if (!mounted) return;
      toast(context, 'PDF добавлен: ${text.length} символов');
    } catch (e) {
      _setBusy(false);
      if (!mounted) return;
      toast(context, 'Ошибка: $e');
    }
  }

  Future<void> _addText() async {
    final titleController = TextEditingController();
    final textController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вставить текст'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: textController,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Текст (учебник, конспект, статья)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (ok == true && textController.text.trim().isNotEmpty) {
      await ref.read(docsProvider.notifier).add(
            title: titleController.text,
            sourceType: 'text',
            content: textController.text,
          );
      if (!mounted) return;
      toast(context, 'Текст добавлен');
    }
    titleController.dispose();
    textController.dispose();
  }

  Future<void> _addObsidian() async {
    final obsidian = ref.read(obsidianProvider);
    if (obsidian.vaultPath == null || obsidian.notes.isEmpty) {
      toast(context, 'Сначала настрой Obsidian (папка Vault) в настройках');
      return;
    }
    final note = await showDialog<dynamic>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Заметка из Vault'),
        children: [
          for (final n in obsidian.notes.take(30))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(n),
              child: Text(n.title,
                  style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
    if (note != null) {
      await ref.read(docsProvider.notifier).add(
            title: note.title,
            sourceType: 'obsidian',
            filePath: note.path,
          );
      if (!mounted) return;
      toast(context, 'Заметка добавлена');
    }
  }

  // ---------------------------------------------------------------- конспект

  Future<void> _makeConspectus() async {
    final docs = ref.read(docsProvider).docs;
    if (docs.isEmpty) {
      toast(context, 'Сначала добавь документы');
      return;
    }
    final doc = await showDialog<SourceDoc>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Конспект чего?'),
        children: [
          for (final d in docs)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(d),
              child: Text(d.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
    if (doc == null) return;

    final screenContext = context;
    _setBusy(true, 'Конспектирую…');
    try {
      final summary = await ref
          .read(docsProvider.notifier)
          .makeConspectus(ref, doc, onProgress: (done, total) {
        if (mounted) {
          setState(() => _busyLabel = 'Конспектирую: раздел $done из $total');
        }
      });
      _setBusy(false);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _ResultSheet(
          title: 'Конспект: ${doc.title}',
          text: summary,
          onSaveObsidian: () async {
            Navigator.of(context).pop();
            final err = await ref.read(obsidianProvider.notifier).createNote(
                  'Конспект ${doc.title}',
                  summary,
                );
            if (!screenContext.mounted) return;
            if (err != null) {
              toast(screenContext, 'Ошибка: $err');
            } else {
              toast(screenContext, 'Конспект сохранён в Obsidian');
            }
          },
          onExportPdf: () async {
            Navigator.of(context).pop();
            try {
              final msg = await FileTools.makePdf(
                title: 'Конспект ${doc.title}',
                text: summary,
              );
              if (screenContext.mounted) toast(screenContext, 'PDF: $msg');
            } catch (e) {
              if (screenContext.mounted) {
                toast(screenContext, 'Ошибка PDF: $e');
              }
            }
          },
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: summary));
            if (!screenContext.mounted) return;
            Navigator.of(screenContext).pop();
            toast(screenContext, 'Конспект скопирован');
          },
        ),
      );
    } catch (e) {
      _setBusy(false);
      if (!mounted) return;
      toast(context, 'Ошибка: $e');
    }
  }

  // ----------------------------------------------------------------- вопросы

  Future<void> _askDocs() async {
    final docs = ref.read(docsProvider).docs;
    if (docs.isEmpty) {
      toast(context, 'Сначала добавь документы');
      return;
    }
    final questionController = TextEditingController();
    final question = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Спросить по документам'),
        content: TextField(
          controller: questionController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Вопрос по учебникам…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(questionController.text.trim()),
            child: const Text('Спросить'),
          ),
        ],
      ),
    );
    if (question == null || question.isEmpty) return;

    _setBusy(true, 'Ищу ответ в документах…');
    try {
      final answer = await ref
          .read(docsProvider.notifier)
          .askDocuments(ref, docs, question);
      _setBusy(false);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ответ'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(answer.text,
                      style: const TextStyle(fontSize: 14, height: 1.5)),
                  const SizedBox(height: 12),
                  const Text('Источники',
                      style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (var i = 0; i < answer.sources.length; i++)
                    Text('${i + 1}. ${answer.sources[i]}',
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (e) {
      _setBusy(false);
      if (!mounted) return;
      toast(context, 'Ошибка: $e');
    }
  }

  // ------------------------------------------------------------------ сборка

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(docsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Документы'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: 'Добавить источник',
            onSelected: (v) {
              switch (v) {
                case 'pdf':
                  _addPdf();
                  break;
                case 'text':
                  _addText();
                  break;
                case 'obsidian':
                  _addObsidian();
                  break;
                case 'record':
                  context.push('/plan_record');
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'pdf', child: Text('📄 PDF-учебник')),
              PopupMenuItem(value: 'text', child: Text('📝 Вставить текст')),
              PopupMenuItem(value: 'obsidian', child: Text('📓 Заметка Obsidian')),
              PopupMenuItem(value: 'record', child: Text('🎙 Запись лекции')),
            ],
          ),
        ],
      ),
      body: _busy
          ? _BusyView(label: _busyLabel)
          : Column(
              children: [
                if (state.docs.isEmpty)
                  const Expanded(child: _EmptyDocs())
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _askDocs,
                            icon: const Icon(Icons.question_answer_outlined,
                                size: 18),
                            label: const Text('Спросить'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _makeConspectus,
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Конспект'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final doc in state.docs)
                          _DocCard(
                            doc: doc,
                            onOpen: () => _viewDoc(doc),
                            onDelete: () async {
                              await ref
                                  .read(docsProvider.notifier)
                                  .remove(doc.id);
                              if (!context.mounted) return;
                              toast(context, 'Удалено');
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _viewDoc(SourceDoc doc) async {
    _setBusy(true, 'Читаю…');
    final content = await ref.read(docsProvider.notifier).loadContent(doc);
    _setBusy(false);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(doc.title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: content.isEmpty
                ? const Text('Источник пуст.',
                    style: TextStyle(color: AppColors.textDim))
                : SelectableText(
                    content.length > 20000
                        ? '${content.substring(0, 20000)}…'
                        : content,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- виджеты

class _BusyView extends StatelessWidget {
  final String label;

  const _BusyView({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }
}

class _EmptyDocs extends StatelessWidget {
  const _EmptyDocs();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 64, color: AppColors.textDim),
            SizedBox(height: 16),
            Text('Пока нет источников',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              'Добавь PDF-учебник, заметку из Obsidian или записанную лекцию — '
              'и задавай вопросы по своим документам.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final SourceDoc doc;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _DocCard({
    required this.doc,
    required this.onOpen,
    required this.onDelete,
  });

  IconData get _icon => switch (doc.sourceType) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'obsidian' => Icons.book_outlined,
        'transcribe' => Icons.mic_outlined,
        _ => Icons.description_outlined,
      };

  String get _typeLabel => switch (doc.sourceType) {
        'pdf' => 'PDF',
        'obsidian' => 'Obsidian',
        'transcribe' => 'Лекция',
        _ => 'Текст',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(_icon, color: AppColors.violet),
        title: Text(doc.title,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '$_typeLabel • ${doc.content.length} симв. • ${fmtDate(doc.addedAt)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 20),
          color: AppColors.textDim,
          tooltip: 'Удалить',
        ),
        onTap: onOpen,
      ),
    );
  }
}

class _ResultSheet extends StatelessWidget {
  final String title;
  final String text;
  final VoidCallback onSaveObsidian;
  final VoidCallback onExportPdf;
  final VoidCallback onCopy;

  const _ResultSheet({
    required this.title,
    required this.text,
    required this.onSaveObsidian,
    required this.onExportPdf,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(text,
                    style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSaveObsidian,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Obsidian'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Копировать'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
