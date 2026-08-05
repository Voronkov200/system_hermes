// Экран "Obsidian Sync Engine": выбор Vault, список заметок, создание.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/obsidian_service.dart';

class ObsidianScreen extends ConsumerWidget {
  const ObsidianScreen({super.key});

  Future<void> _createNote(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Новая заметка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Содержимое (Markdown)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final error = await ref.read(obsidianProvider.notifier).createNote(
          titleController.text,
          contentController.text,
        );
    if (error != null && context.mounted) toast(context, error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obsidian = ref.watch(obsidianProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Obsidian Vault'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Новая заметка',
            onPressed: () => _createNote(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: () => ref.read(obsidianProvider.notifier).refresh(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Выбор папки Vault
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      color: obsidian.vaultPath == null
                          ? AppColors.textDim
                          : AppColors.violet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(obsidian.vaultPath ?? 'Vault не выбран',
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          obsidian.watching
                              ? '● слежение активно'
                              : 'слежение выключено',
                          style: TextStyle(
                            fontSize: 11,
                            color: obsidian.watching
                                ? AppColors.accent
                                : AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await ref.read(obsidianProvider.notifier).pickVault();
                      if (context.mounted) {
                        toast(context, 'Папка Vault выбрана');
                      }
                    },
                    child: const Text('Выбрать'),
                  ),
                ],
              ),
            ),
          ),

          if (obsidian.error != null) ...[
            const SizedBox(height: 12),
            Text(obsidian.error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ],

          const SizedBox(height: 16),
          Text('ЗАМЕТКИ (${obsidian.notes.length})',
              style: const TextStyle(
                  fontSize: 12, letterSpacing: 1, color: AppColors.textDim)),
          const SizedBox(height: 8),

          if (obsidian.loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (obsidian.notes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Заметок нет. Создай первую или синхронизируй Vault.',
                  style: TextStyle(color: AppColors.textDim)),
            )
          else
            ...obsidian.notes.map((n) {
              return Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined,
                      size: 20, color: AppColors.violet),
                  title: Text(n.title,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(fmtDateTime(n.modifiedAt),
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => context.push('/note', extra: n.path),
                ),
              );
            }),
        ],
      ),
    );
  }
}
