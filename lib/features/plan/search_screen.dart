// Экран "Поиск" — агентный режим с прозрачным процессом исследования:
// план → запросы → источники → факты → проверка → ответ + timeline.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/plan/agent_run.dart';
import '../../services/plan/article_service.dart';
import '../../services/plan/search_service.dart';
import '../../services/settings_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  bool _deep = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Если текст похож на сбой распознавания — показать диалог
  /// с редактируемой фразой. Возвращает исправленный текст или null.
  Future<String?> _confirmIfBroken(String q) async {
    final reason = SearchService.looksBrokenSpeech(q);
    if (reason == null) return q;
    final controller = TextEditingController(text: q);
    final res = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Похоже, я неправильно распознал текст'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Я услышал: «$q» ($reason). Поправь текст или нажми «Искать».',
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Текст'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Искать'),
          ),
        ],
      ),
    );
    return res;
  }

  Future<void> _run() async {
    var q = _controller.text.trim();
    final running = ref.read(searchRunProvider).phase != AgentPhase.idle &&
        ref.read(searchRunProvider).phase != AgentPhase.completed &&
        ref.read(searchRunProvider).phase != AgentPhase.failed;
    if (q.isEmpty || running) return;
    final confirmed = await _confirmIfBroken(q);
    if (!mounted || confirmed == null) return;
    q = confirmed.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    await ref.read(searchRunProvider.notifier).start(query: q, deep: _deep);
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(settingsProvider).searchOffline;
    final run = ref.watch(searchRunProvider);
    final running = run.phase != AgentPhase.idle &&
        run.phase != AgentPhase.completed &&
        run.phase != AgentPhase.failed;

    return Scaffold(
      appBar: AppBar(title: const Text('Поиск')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _run(),
                        maxLength: 500,
                        decoration: const InputDecoration(
                          hintText: 'Спроси что угодно…',
                          prefixIcon: Icon(Icons.travel_explore),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: () => ref
                          .read(settingsProvider.notifier)
                          .setSearchOffline(!offline),
                      icon: Icon(offline ? Icons.wifi_off : Icons.wifi),
                      tooltip: offline
                          ? 'Офлайн-режим включён — поиск отключён'
                          : 'Офлайн-режим: отвечать без интернета',
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: running ? null : _run,
                      icon: const Icon(Icons.search),
                      tooltip: 'Искать',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Быстрый поиск'),
                            icon: Icon(Icons.bolt, size: 16),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Глубокое исследование'),
                            icon: Icon(Icons.science_outlined, size: 16),
                          ),
                        ],
                        selected: {_deep},
                        onSelectionChanged: running
                            ? null
                            : (s) => setState(() => _deep = s.first),
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (run.phase) {
              AgentPhase.idle => const _WelcomeView(),
              AgentPhase.completed ||
              AgentPhase.failed =>
                _DoneView(run: run, onNewSearch: () {
                  ref.read(searchRunProvider.notifier).stop();
                  ref.invalidate(searchRunProvider);
                  setState(() {});
                }),
              _ => _ProcessView(run: run, deep: _deep),
            },
          ),
        ],
      ),
    );
  }
}

/// Подписи и иконки фаз (раздел 26 спецификации).
({String label, IconData icon}) _phaseMeta(AgentPhase phase) =>
    switch (phase) {
      AgentPhase.idle => (label: '', icon: Icons.travel_explore),
      AgentPhase.analyzing => (label: 'Анализирую запрос', icon: Icons.psychology),
      AgentPhase.planning => (label: 'Создаю план поиска', icon: Icons.list_alt),
      AgentPhase.searching => (label: 'Ищу в интернете', icon: Icons.search),
      AgentPhase.evaluatingResults =>
        (label: 'Оцениваю результаты', icon: Icons.rule),
      AgentPhase.openingSources =>
        (label: 'Открываю страницы', icon: Icons.web),
      AgentPhase.extractingEvidence =>
        (label: 'Извлекаю факты', icon: Icons.manage_search),
      AgentPhase.checkingConflicts =>
        (label: 'Проверяю противоречия', icon: Icons.warning_amber),
      AgentPhase.additionalSearch =>
        (label: 'Дополнительный поиск', icon: Icons.travel_explore),
      AgentPhase.synthesizing => (label: 'Формирую ответ', icon: Icons.psychology),
      AgentPhase.verifying => (label: 'Проверяю ответ', icon: Icons.fact_check),
      AgentPhase.completed => (label: 'Готово', icon: Icons.check_circle),
      AgentPhase.failed => (label: 'Не удалось', icon: Icons.error_outline),
    };

/// Иконка события timeline (раздел 19 спецификации).
IconData _eventIcon(AgentEventType type) => switch (type) {
      AgentEventType.searchPlanCreated => Icons.psychology,
      AgentEventType.searchQueryStarted => Icons.search,
      AgentEventType.searchResultsReceived => Icons.public,
      AgentEventType.sourceSelected => Icons.task_alt,
      AgentEventType.sourceOpened => Icons.web_asset,
      AgentEventType.sourceRejected => Icons.cancel_outlined,
      AgentEventType.factExtracted => Icons.manage_search,
      AgentEventType.factConflictFound => Icons.warning_amber,
      AgentEventType.followUpSearchStarted => Icons.travel_explore,
      AgentEventType.synthesisStarted => Icons.psychology,
      AgentEventType.finalAnswerCreated => Icons.verified_outlined,
    };

/// Прогресс по фазе — для полосы (раздел 18 спецификации).
double _phaseProgress(AgentPhase phase) => switch (phase) {
      AgentPhase.idle => 0,
      AgentPhase.analyzing => 0.08,
      AgentPhase.planning => 0.18,
      AgentPhase.searching => 0.4,
      AgentPhase.evaluatingResults => 0.5,
      AgentPhase.openingSources => 0.62,
      AgentPhase.extractingEvidence => 0.72,
      AgentPhase.checkingConflicts => 0.8,
      AgentPhase.additionalSearch => 0.86,
      AgentPhase.synthesizing => 0.94,
      AgentPhase.verifying => 0.98,
      AgentPhase.completed => 1,
      AgentPhase.failed => 1,
    };

/// Живой экран процесса исследования (раздел 18 спецификации).
class _ProcessView extends ConsumerWidget {
  final AgentRunState run;
  final bool deep;

  const _ProcessView({required this.run, required this.deep});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = _phaseMeta(run.phase);
    final progress = _phaseProgress(run.phase);
    final now = run.events.isEmpty
        ? null
        : run.events.last;
    final openedCount = run.sources.where((s) => s.opened).length;

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
                  run.query,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  deep ? 'Глубокое исследование' : 'Быстрый поиск',
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(meta.icon, size: 20, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        meta.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (run.plan.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.list_alt,
            title: 'План поиска',
            children: [
              for (final step in run.plan)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.w700)),
                      Expanded(child: Text(step, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (run.queries.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.search,
            title: 'Поисковые запросы',
            children: [
              for (final q in run.queries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(q, style: const TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ],
        if (run.events.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.timeline,
            title: 'Журнал действий',
            children: [
              for (final e in run.events)
                _TimelineTile(event: e, isLast: identical(e, now)),
            ],
          ),
        ],
        if (run.sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.web,
            title: openedCount > 0
                ? 'Сейчас изучаю ($openedCount)'
                : 'Источники',
            children: [
              for (final s in run.sources)
                if (s.status != SourceStatus.rejected)
                  _SourceStatusTile(source: s, showScore: false),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.cyan),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final AgentEvent event;
  final bool isLast;

  const _TimelineTile({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = switch (event.status) {
      AgentEventStatus.active => AppColors.cyan,
      AgentEventStatus.done => AppColors.textDim,
      AgentEventStatus.error => AppColors.danger,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_eventIcon(event.type), size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 13,
                    color: isLast ? AppColors.cyan : AppColors.textPrimary,
                    fontWeight:
                        isLast ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (event.description != null &&
                    event.description!.isNotEmpty)
                  Text(
                    event.description!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                      height: 1.35,
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

/// Источник со статусом (раздел 21 спецификации).
class _SourceStatusTile extends StatelessWidget {
  final AgentSource source;
  final bool showScore;

  const _SourceStatusTile({
    required this.source,
    this.showScore = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (source.status) {
      SourceStatus.used => AppColors.accent,
      SourceStatus.found => AppColors.cyan,
      SourceStatus.opened => AppColors.cyan,
      SourceStatus.rejected => AppColors.textDim,
      SourceStatus.conflicting => AppColors.warning,
    };
    final icon = switch (source.status) {
      SourceStatus.used => Icons.check_circle_outline,
      SourceStatus.found => Icons.radio_button_unchecked,
      SourceStatus.opened => Icons.radio_button_checked,
      SourceStatus.rejected => Icons.cancel_outlined,
      SourceStatus.conflicting => Icons.warning_amber_outlined,
    };
    final label = switch (source.status) {
      SourceStatus.used => 'Used',
      SourceStatus.found => 'Found',
      SourceStatus.opened => 'Opened',
      SourceStatus.rejected => 'Rejected',
      SourceStatus.conflicting => 'Conflicting',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  source.hit.title.isEmpty ? source.hit.url : source.hit.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (showScore)
                Text(
                  '${source.score.round()}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ),
          if (source.reason != null)
            Padding(
              padding: const EdgeInsets.only(left: 21),
              child: Text(
                source.reason!,
                style: const TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
            ),
        ],
      ),
    );
  }
}

/// Результат: сводка + ответ + кнопка «Показать процесс поиска».
class _DoneView extends ConsumerWidget {
  final AgentRunState run;
  final VoidCallback onNewSearch;

  const _DoneView({required this.run, required this.onNewSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (run.phase == AgentPhase.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(
                run.error ?? 'Не удалось выполнить поиск',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onNewSearch,
                icon: const Icon(Icons.refresh),
                label: const Text('Новый поиск'),
              ),
            ],
          ),
        ),
      );
    }
    final answer = run.answer;
    if (answer == null) return const SizedBox.shrink();
    return _AnswerView(
      run: run,
      answer: answer,
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
              'и покажу процесс исследования, как DeepSeek.',
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
  final AgentRunState run;
  final SearchAnswer answer;

  const _AnswerView({required this.run, required this.answer});

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
        title: widget.run.query,
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
    final run = widget.run;
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
                  run.query,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmtDate(DateTime.now())} · '
                  '${run.elapsed.inSeconds} сек',
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                if (run.summary.isNotEmpty) ...[
                  Text(
                    run.summary,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDim,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
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
        if (run.events.isNotEmpty || run.plan.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ProcessCard(run: run),
        ],
        if (SearchService.log.isNotEmpty) ...[
          const SizedBox(height: 8),
          const _SearchLogCard(),
        ],
      ],
    );
  }
}

/// Сворачиваемая карточка «Показать процесс поиска» (раздел 22 спецификации).
class _ProcessCard extends StatelessWidget {
  final AgentRunState run;

  const _ProcessCard({required this.run});

  @override
  Widget build(BuildContext context) {
    final used = run.sources.where((s) => s.status == SourceStatus.used).length;
    final opened = run.sources.where((s) => s.opened).length;
    final rejected =
        run.sources.where((s) => s.status == SourceStatus.rejected).length;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        title: const Text(
          'Показать процесс поиска',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${run.plan.length} шагов плана · ${run.queries.length} запросов · '
          '$opened открыто · $used использовано · $rejected отброшено',
          style: const TextStyle(fontSize: 11),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (run.plan.isNotEmpty) ...[
            const _MiniHeader('План'),
            for (final p in run.plan)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $p', style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 10),
          ],
          if (run.queries.isNotEmpty) ...[
            const _MiniHeader('Запросы'),
            for (final q in run.queries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $q', style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 10),
          ],
          if (run.sources.isNotEmpty) ...[
            const _MiniHeader('Источники'),
            for (final s in run.sources) _SourceStatusTile(source: s),
            const SizedBox(height: 10),
          ],
          const _MiniHeader('Журнал действий'),
          for (final e in run.events) _TimelineTile(event: e, isLast: false),
        ],
      ),
    );
  }
}

class _MiniHeader extends StatelessWidget {
  final String text;

  const _MiniHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textDim,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Технический лог поиска: что искали, каким провайдером, что нашли.
class _SearchLogCard extends StatelessWidget {
  const _SearchLogCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 4),
      child: ExpansionTile(
        dense: true,
        title: const Text(
          'Технический лог',
          style: TextStyle(fontSize: 12, color: AppColors.textDim),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          SelectableText(
            SearchService.log.join('\n'),
            style: const TextStyle(fontSize: 11, height: 1.4),
          ),
        ],
      ),
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
