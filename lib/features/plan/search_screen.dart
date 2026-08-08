// Экран "Поиск" (в стиле Morphic/NotebookLM Research):
// вопрос → интернет → ответ с цитатами источников.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/agent/file_tools.dart';
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
  bool _savingArticle = false;
  bool _savingPdf = false;

  Future<void> _makeArticle() async {
    if (_savingArticle) return;
    setState(() => _savingArticle = true);
    try {
      final path = await ArticleService.saveArticle(
        ref,
        title: widget.query,
        text: widget.answer.text,
        sources: widget.answer.sources,
      );
      if (!mounted) return;
      context.push('/web', extra: path);
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Не удалось создать статью: $e');
    } finally {
      if (mounted) setState(() => _savingArticle = false);
    }
  }

  Future<void> _makePdf() async {
    if (_savingPdf) return;
    setState(() => _savingPdf = true);
    try {
      final msg = await FileTools.makePdf(
        title: widget.query,
        text: widget.answer.text,
      );
      if (!mounted) return;
      toast(context, msg);
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Не удалось создать PDF: $e');
    } finally {
      if (mounted) setState(() => _savingPdf = false);
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
                SelectableText(
                  answer.text,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _savingArticle ? null : _makeArticle,
                      icon: _savingArticle
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.article_outlined, size: 18),
                      label: const Text('Оформить статью'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _savingPdf ? null : _makePdf,
                      icon: _savingPdf
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF'),
                    ),
                  ],
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
