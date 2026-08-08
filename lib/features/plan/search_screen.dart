// Экран "Поиск" (в стиле Morphic/NotebookLM Research):
// вопрос → интернет → ответ с цитатами источников.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
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
                            : _AnswerView(answer: _answer!),
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

class _AnswerView extends StatelessWidget {
  final SearchAnswer answer;

  const _AnswerView({required this.answer});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              answer.text,
              style: const TextStyle(fontSize: 14, height: 1.5),
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
