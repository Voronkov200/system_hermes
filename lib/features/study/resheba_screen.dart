// Экран решений заданий с resheba.top: главы → номера → фото решения.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/study/resheba_service.dart';

class ReshebaScreen extends StatefulWidget {
  final String subjectTitle;
  final String subjectId;

  const ReshebaScreen({
    super.key,
    required this.subjectTitle,
    required this.subjectId,
  });

  @override
  State<ReshebaScreen> createState() => _ReshebaScreenState();
}

class _ReshebaScreenState extends State<ReshebaScreen> {
  late Future<ReshebaBook> _bookFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _bookFuture = ReshebaService().loadBook(widget.subjectTitle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ГДЗ · ${widget.subjectTitle}'),
        actions: [
          IconButton(
            tooltip: 'Открыть источник',
            onPressed: () => context.push(
              '/web',
              extra: 'https://resheba.top/gdz/11-klass',
            ),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: FutureBuilder<ReshebaBook>(
        future: _bookFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    'Загрузка решений…',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      color: AppColors.danger,
                      size: 38,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Не удалось загрузить решения:\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => setState(() {
                        _bookFuture = ReshebaService().loadBook(
                          widget.subjectTitle,
                        );
                      }),
                      child: const Text('Повторить'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => context.push(
                        '/web',
                        extra: 'https://resheba.top/gdz/11-klass',
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Открыть сайт'),
                    ),
                  ],
                ),
              ),
            );
          }
          final book = snap.data!;
          final filtered = <(ReshebaSection, List<int>)>[];
          final cleaned = _query.trim().toLowerCase();
          final requestedNumber = int.tryParse(cleaned);
          for (final section in book.sections) {
            if (cleaned.isEmpty) {
              filtered.add((section, section.numbers));
            } else if (requestedNumber != null) {
              if (section.numbers.contains(requestedNumber)) {
                filtered.add((section, [requestedNumber]));
              }
            } else if (section.text.toLowerCase().contains(cleaned)) {
              filtered.add((section, section.numbers));
            }
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.cyan.withValues(alpha: .18),
                      AppColors.violet.withValues(alpha: .07),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.cyan.withValues(alpha: .35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.photo_library_outlined,
                            color: AppColors.cyan),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${book.totalNumbers} решений в фото',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: (book.fromCache
                                    ? AppColors.warning
                                    : AppColors.accent)
                                .withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            book.fromCache ? 'из кэша' : 'каталог обновлён',
                            style: TextStyle(
                              color: book.fromCache
                                  ? AppColors.warning
                                  : AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Введи номер задания или открой нужный раздел. Первое '
                      'открытие фото требует интернет; затем оно остаётся на '
                      'телефоне.',
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                keyboardType: TextInputType.number,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Номер задания, например 12',
                  suffixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.search_off, color: AppColors.textDim),
                        SizedBox(height: 8),
                        Text(
                          'Такого номера в этой редакции решебника нет.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textDim),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final entry in filtered) ...[
                _SectionCard(
                  subjectTitle: widget.subjectTitle,
                  subjectId: widget.subjectId,
                  book: book,
                  section: entry.$1,
                  visibleNumbers: entry.$2,
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatefulWidget {
  final String subjectTitle;
  final String subjectId;
  final ReshebaBook book;
  final ReshebaSection section;
  final List<int> visibleNumbers;

  const _SectionCard({
    required this.subjectTitle,
    required this.subjectId,
    required this.book,
    required this.section,
    required this.visibleNumbers,
  });

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final numbers = widget.visibleNumbers;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _open || numbers.length == 1,
        onExpansionChanged: (v) => setState(() => _open = v),
        title: Text(
          widget.section.text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${numbers.length} заданий',
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in numbers)
                  _NumberChip(
                    label: '$n',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _PhotoScreen(
                          subjectTitle: widget.subjectTitle,
                          book: widget.book,
                          section: widget.section,
                          index: numbers.indexOf(n),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NumberChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Просмотр фото решения с навигацией по соседним номерам.
class _PhotoScreen extends StatefulWidget {
  final String subjectTitle;
  final ReshebaBook book;
  final ReshebaSection section;
  final int index;

  const _PhotoScreen({
    required this.subjectTitle,
    required this.book,
    required this.section,
    required this.index,
  });

  @override
  State<_PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<_PhotoScreen> {
  late int _index;
  late Future<File> _photoFuture;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _photoFuture = _loadCurrent();
  }

  int get _current => widget.section.numbers[_index];

  void _move(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.section.numbers.length) return;
    setState(() {
      _index = next;
      _photoFuture = _loadCurrent();
    });
  }

  Future<File> _loadCurrent() => ReshebaService().loadPhoto(
        widget.subjectTitle,
        widget.book,
        widget.section,
        _current,
      );

  void _retry() {
    setState(() => _photoFuture = _loadCurrent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Задание ${widget.section.text} · №$_current',
        ),
        actions: [
          IconButton(
            tooltip: 'Предыдущее',
            icon: const Icon(Icons.chevron_left),
            onPressed: _index > 0 ? () => _move(-1) : null,
          ),
          IconButton(
            tooltip: 'Следующее',
            icon: const Icon(Icons.chevron_right),
            onPressed: _index < widget.section.numbers.length - 1
                ? () => _move(1)
                : null,
          ),
        ],
      ),
      body: FutureBuilder<File>(
        future: _photoFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined,
                        color: AppColors.danger),
                    const SizedBox(height: 10),
                    Text(
                      'Не удалось загрузить решение №$_current:\n'
                      '${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }
          final file = snap.data!;
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text('Фото повреждено'),
              ),
            ),
          );
        },
      ),
    );
  }
}
