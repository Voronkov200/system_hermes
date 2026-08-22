// Экран "Журнал": табличка всех изменений и записей системы.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/journal_service.dart';

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String _query = '';
  String _filter = '';

  static const _typeIcons = <String, IconData>{
    'voice': Icons.mic,
    'file': Icons.insert_drive_file_outlined,
    'pdf': Icons.picture_as_pdf_outlined,
    'task': Icons.checklist,
    'note': Icons.description_outlined,
    'study': Icons.school_outlined,
    'system': Icons.settings_suggest_outlined,
  };

  static const _typeColors = <String, Color>{
    'voice': AppColors.violet,
    'file': AppColors.cyan,
    'pdf': AppColors.danger,
    'task': AppColors.warning,
    'note': AppColors.accent,
    'study': AppColors.cyan,
    'system': AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(journalProvider).entries;

    final visible = entries.where((e) {
      final q = _query.trim().toLowerCase();
      final matchesQuery = q.isEmpty ||
          e.title.toLowerCase().contains(q) ||
          e.text.toLowerCase().contains(q);
      final matchesFilter = _filter.isEmpty || e.type == _filter;
      return matchesQuery && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал изменений'),
        actions: [
          IconButton(
            icon: const Icon(Icons.post_add),
            tooltip: 'Добавить запись',
            onPressed: _addManualEntry,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Очистить журнал',
            onPressed: entries.isEmpty
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Очистить журнал?'),
                        content: Text('Будет удалено ${entries.length} записей.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Очистить'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(journalProvider.notifier).clear();
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Поиск по журналу…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                _filterChip('', 'Все'),
                for (final t in _typeIcons.keys) _filterChip(t, _label(t)),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text('Пусто. Спроси Hermes '
                        '«добавь в журнал …»\nили надиктуй голосовое — '
                        'всё попадёт сюда.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textDim)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = visible[i];
                      return Dismissible(
                        key: ValueKey(e.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) =>
                            ref.read(journalProvider.notifier).remove(e.id),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: Colors.white),
                        ),
                        child: _EntryTile(entry: e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  String _label(String t) => switch (t) {
        'voice' => 'Голос',
        'file' => 'Файлы',
        'pdf' => 'PDF',
        'task' => 'Задачи',
        'note' => 'Заметки',
        'study' => 'Учёба',
        _ => 'Система',
      };

  Future<void> _addManualEntry() async {
    final title = TextEditingController();
    final text = TextEditingController();
    String type = 'system';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Запись в журнал'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                items: _typeIcons.keys
                    .map((t) => DropdownMenuItem(value: t, child: Text(_label(t))))
                    .toList(),
                onChanged: (v) => setDialogState(() => type = v ?? 'system'),
                decoration: const InputDecoration(
                    labelText: 'Тип', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: title,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                    labelText: 'Название', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: text,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                    labelText: 'Содержание', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                ref.read(journalProvider.notifier).add(
                      type: type,
                      source: 'user',
                      title: title.text,
                      text: text.text,
                    );
                Navigator.pop(ctx);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final JournalEntry entry;

  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final icon = _JournalScreenState._typeIcons[entry.type] ??
        Icons.info_outline;
    final color = _JournalScreenState._typeColors[entry.type] ??
        AppColors.textDim;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                fmtTime(entry.date),
                style: const TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
            ],
          ),
          if (entry.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              entry.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textDim),
            ),
          ],
        ],
      ),
    );
  }
}
