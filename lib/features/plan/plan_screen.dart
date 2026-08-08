// Экран "План": задачи, которые ставят Hermes и Настя.
// Создание, выполнение и удаление задач прямо с экрана.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/tasks_service.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).tasks;
    final open = tasks.where((t) => t.status == 'open').toList();
    final done = tasks.where((t) => t.status == 'done').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('План'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Text(
                  'Открыто: ${open.length}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: tasks.isEmpty
          ? _EmptyPlan(onAdd: () => _addTaskDialog(context, ref))
          : _TaskList(open: open, done: done),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTaskDialog(context, ref),
        tooltip: 'Новая задача',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyPlan({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.checklist, size: 64, color: AppColors.textDim),
            const SizedBox(height: 16),
            const Text(
              'Задач пока нет',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Попроси Hermes или Настю в чате поставить задачу — '
              'она появится здесь. Или добавь свою.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Добавить задачу'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  final List<HermesTask> open;
  final List<HermesTask> done;

  const _TaskList({required this.open, required this.done});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final task in open) _TaskCard(task: task),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Выполнено (${done.length})',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final task in done) _TaskCard(task: task, done: true),
        ],
      ],
    );
  }
}

class _TaskCard extends ConsumerWidget {
  final HermesTask task;
  final bool done;

  const _TaskCard({required this.task, this.done = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = done ? AppColors.textDim : AppColors.accent;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: done
                  ? null
                  : () => ref.read(tasksProvider.notifier).markDone(task.id),
              child: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: done ? AppColors.accent : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent),
                ),
                child: done
                    ? const Icon(Icons.check, size: 16, color: AppColors.bg)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.textDim,
                      color: done ? AppColors.textDim : null,
                    ),
                  ),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    done
                        ? 'Выполнено ${fmtDateTime(task.doneAt ?? task.createdAt)}'
                        : 'Создано ${fmtDateTime(task.createdAt)}',
                    style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (done)
              IconButton(
                onPressed: () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.textDim,
                tooltip: 'Удалить',
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text('«${task.title}» будет удалена безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(tasksProvider.notifier).removeTask(task.id);
              toast(context, 'Задача удалена');
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

void _addTaskDialog(BuildContext context, WidgetRef ref) {
  final screenContext = context;
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Новая задача'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleController,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Что нужно сделать',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: descriptionController,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Подробности (необязательно)',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final title = titleController.text.trim();
            if (title.isEmpty) return;
            Navigator.of(context).pop();
            ref.read(tasksProvider.notifier).addTask(
                  title,
                  descriptionController.text.trim(),
                );
            toast(screenContext, 'Задача добавлена в план');
          },
          child: const Text('Добавить'),
        ),
      ],
    ),
  );
}
