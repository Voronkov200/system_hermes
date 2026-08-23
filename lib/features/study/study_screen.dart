// Экран «Учёба»: предметы 11 класса и дополнительная литература.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/study/resheba_service.dart';
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

class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  String _query = '';
  String _category = 'Все';

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(studyProvider);
    bool matches(StudySubject subject) {
      final query = _query.trim().toLowerCase();
      final queryMatches = query.isEmpty ||
          subject.title.toLowerCase().contains(query) ||
          subject.subtitle.toLowerCase().contains(query);
      final categoryMatches =
          _category == 'Все' || subject.category == _category;
      return queryMatches && categoryMatches;
    }

    final subjects = st.subjects
        .where((s) => s.kind == 'subject' && matches(s))
        .toList();
    final guides = st.subjects
        .where((s) => s.kind == 'guide' && matches(s))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Учёба'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Дополнительно',
            onSelected: (value) {
              if (value == 'import') _importJson(context, ref);
              if (value == 'subject') _addManualSubject(context, ref);
              if (value == 'guide') _addGuide(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_file),
                  title: Text('Импорт JSON'),
                ),
              ),
              PopupMenuItem(
                value: 'subject',
                child: ListTile(
                  leading: Icon(Icons.add),
                  title: Text('Добавить предмет'),
                ),
              ),
              PopupMenuItem(
                value: 'guide',
                child: ListTile(
                  leading: Icon(Icons.library_add_outlined),
                  title: Text('Добавить пособие'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StudyOverview(state: st),
          const SizedBox(height: 14),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Найти предмет',
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final category in const [
                  'Все',
                  'Точные науки',
                  'Языки',
                  'Гуманитарные',
                ]) ...[
                  ChoiceChip(
                    label: Text(category),
                    selected: _category == category,
                    onSelected: (_) =>
                        setState(() => _category = category),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (st.error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                st.error!,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 11,
                ),
              ),
            ),
          ],
          if (st.bundledTotal > 0 && st.bundledDone < st.bundledTotal) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Загрузка разборов учебников… '
                      '${st.bundledDone}/${st.bundledTotal}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: st.bundledTotal == 0
                          ? null
                          : st.bundledDone / st.bundledTotal,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: 18),
            _Header('Предметы 11 класса · ${subjects.length}'),
            const SizedBox(height: 8),
            for (final s in subjects) ...[
              _SubjectCard(subject: s),
              const SizedBox(height: 10),
            ],
          ],
          if (subjects.isEmpty && guides.isEmpty) ...[
            const SizedBox(height: 24),
            const Center(
              child: Column(
                children: [
                  Icon(Icons.search_off, color: AppColors.textDim, size: 36),
                  SizedBox(height: 8),
                  Text(
                    'Ничего не найдено',
                    style: TextStyle(color: AppColors.textDim),
                  ),
                ],
              ),
            ),
          ],
          if (guides.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _Header('Дополнительная литература'),
            const SizedBox(height: 8),
            for (final g in guides) ...[
              _SubjectCard(subject: g),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 28),
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

  Future<void> _importJson(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var ok = 0;
    var skipped = 0;
    for (final f in result.files) {
      final path = f.path;
      if (path == null) {
        skipped++;
        continue;
      }
      try {
        await ref.read(studyProvider.notifier).importParsedBook(path);
        ok++;
      } catch (e) {
        skipped++;
        messenger.showSnackBar(
          SnackBar(content: Text('«${f.name}»: $e')),
        );
      }
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok > 0 ? 'Импортировано файлов: $ok' : 'Ничего не импортировано',
        ),
      ),
    );
    if (skipped > 0 && ok > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('Пропущено: $skipped (см. ошибки выше)')),
      );
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

class _StudyOverview extends StatelessWidget {
  final StudyState state;

  const _StudyOverview({required this.state});

  @override
  Widget build(BuildContext context) {
    final subjectCount = state.subjects.where((s) => s.kind == 'subject').length;
    final learned = state.paragraphs.where((p) => p.learned).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: .2),
            AppColors.cyan.withValues(alpha: .06),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.accent.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.school_outlined, color: AppColors.accent),
              SizedBox(width: 9),
              Text(
                '11 класс · локальная библиотека',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Тексты учебников находятся на телефоне. Фото ГДЗ загружаются '
            'по номеру один раз и сохраняются в кэше.',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StudyMetric(value: '$subjectCount', label: 'предметов'),
              const SizedBox(width: 8),
              _StudyMetric(value: '${state.paragraphs.length}', label: 'параграфов'),
              const SizedBox(width: 8),
              _StudyMetric(value: '$learned', label: 'изучено'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudyMetric extends StatelessWidget {
  final String value;
  final String label;

  const _StudyMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: AppColors.textDim, fontSize: 10),
              ),
            ],
          ),
        ),
      );
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
    final learned = st.paragraphs
        .where((p) => p.subjectId == subject.id && p.learned)
        .length;
    final hasGdz = ReshebaService.jsPathFor(subject.title) != null;
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
                        '$learned/$count изучено · '
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
              if (hasGdz)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'ФОТО ГДЗ',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
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
