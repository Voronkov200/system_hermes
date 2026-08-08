// Экран "Поиск" (в стиле Morphic/NotebookLM Research):
// вопрос → интернет → ответ с цитатами источников.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/plan/article_service.dart';
import '../../services/plan/search_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  bool _busy = false;
  String _stage = '';
  String? _error;
  SearchAnswer? _answer;
  String _lastQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run([String? query]) async {
    final q = (query ?? _controller.text).trim();
    if (q.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _stage = 'Ищу в интернете…';
      _error = null;
      _answer = null;
      _lastQuery = q;
    });
    try {
      final answer = await SearchService.ask(
        ref,
        q,
        onStage: (s) => setState(() => _stage = s),
      );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _run,
                    decoration: const InputDecoration(
                      hintText: 'Спроси что угодно…',
                      prefixIcon: Icon(Icons.travel_explore),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _busy ? null : _run,
                  icon: const Icon(Icons.search),
                  tooltip: 'Искать',
                ),
              ],
            ),
          ),
          Expanded(
            child: _busy
                ? _BusyView(stage: _stage)
                : _error != null
                    ? _ErrorView(message: _error!)
                        : _answer == null
                            ? const _WelcomeView()
                            : _AnswerView(
                                answer: _answer!,
                                query: _lastQuery,
                              ),
          ),
        ],
      ),
    );
  }
}

class _BusyView extends StatelessWidget {
  final String stage;

  const _BusyView({required this.stage});

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
            Text(stage, style: const TextStyle(color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore, size: 64, color: AppColors.cyan),
            SizedBox(height: 16),
            Text(
              'Задай вопрос — я найду ответ в интернете\n'
              'и покажу источники, как NotebookLM.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerView extends ConsumerStatefulWidget {
  final SearchAnswer answer;
  final String query;

  const _AnswerView({required this.answer, required this.query});

  @override
  ConsumerState<_AnswerView> createState() => _AnswerViewState();
}

class _AnswerViewState extends ConsumerState<_AnswerView> {
  bool _saving = false;

  Future<void> _chooseSave() async {
    final choice = await showDialog<({String format, String folder})>(
      context: context,
      builder: (context) => const _SaveDialog(),
    );
    if (choice == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final path = await ArticleService.save(
        ref,
        title: widget.query,
        text: widget.answer.text,
        sources: widget.answer.sources,
        format: choice.format,
        folder: choice.folder,
      );
      if (!mounted) return;
      if (choice.format == 'article') {
        context.push('/web', extra: path);
      } else {
        toast(context, 'Сохранено: $path');
      }
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answer = widget.answer;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.query,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fmtDate(DateTime.now()),
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _AnswerText(text: answer.text, sources: answer.sources),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _chooseSave,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Сохранить…'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Источники',
          style: TextStyle(
            color: AppColors.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < answer.sources.length; i++)
          _SourceTile(index: i + 1, hit: answer.sources[i]),
      ],
    );
  }
}

/// Ответ с кликабельными цитатами [1], [2]… — открывают источник.
class _AnswerText extends StatelessWidget {
  final String text;
  final List<SearchHit> sources;

  const _AnswerText({required this.text, required this.sources});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in RegExp(r'\[(\d{1,2})\]').allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      final idx = int.tryParse(m.group(1) ?? '') ?? 0;
      final url = (idx >= 1 && idx <= sources.length)
          ? sources[idx - 1].url
          : null;
      spans.add(
        url == null
            ? TextSpan(text: m.group(0))
            : TextSpan(
                text: m.group(0),
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w700,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => context.push('/web', extra: url),
              ),
      );
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(fontSize: 14, height: 1.55),
    );
  }
}

/// Диалог: формат сохранения и папка назначения.
class _SaveDialog extends StatefulWidget {
  const _SaveDialog();

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  String _format = 'article';
  String _folder = 'docs/статьи';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Сохранить ответ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Формат', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final e in ArticleService.formats.entries)
                ChoiceChip(
                  label: Text(e.value.$1),
                  selected: _format == e.key,
                  onSelected: (_) => setState(() => _format = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Куда сохранить', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final e in ArticleService.folders.entries)
                ChoiceChip(
                  label: Text(e.key),
                  selected: _folder == e.value,
                  onSelected: (_) => setState(() => _folder = e.value),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Файл попадёт в SystemHermes/'
            '${_folder.isEmpty ? '(корень)' : _folder}/',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            (format: _format, folder: _folder),
          ),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  final int index;
  final SearchHit hit;

  const _SourceTile({required this.index, required this.hit});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '[$index]',
            style: const TextStyle(
              color: AppColors.cyan,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        title: Text(
          hit.title.isEmpty ? hit.url : hit.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: hit.snippet.isEmpty
            ? null
            : Text(
                hit.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
        onTap: () => context.push('/web', extra: hit.url),
      ),
    );
  }
}
