// Агентный поиск: модель «прозрачного процесса исследования».
//
// Пользователь видит не chain-of-thought модели, а наблюдаемые действия
// агента (план, запросы, открытые страницы, факты, противоречия,
// дополнительные поиски) — AgentEvent Timeline, как в DeepSeek Research.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_service.dart';

/// Состояния агента (раздел 26 спецификации).
enum AgentPhase {
  idle,
  analyzing,
  planning,
  searching,
  evaluatingResults,
  openingSources,
  extractingEvidence,
  checkingConflicts,
  additionalSearch,
  synthesizing,
  verifying,
  completed,
  failed,
}

/// Типы событий журнала агента (раздел 2 спецификации).
enum AgentEventType {
  searchPlanCreated,
  searchQueryStarted,
  searchResultsReceived,
  sourceSelected,
  sourceOpened,
  sourceRejected,
  factExtracted,
  factConflictFound,
  followUpSearchStarted,
  synthesisStarted,
  finalAnswerCreated,
}

/// Статус события в timeline.
enum AgentEventStatus { active, done, error }

/// Статус источника (раздел 21 спецификации).
enum SourceStatus { found, opened, used, rejected, conflicting }

/// Одно действие агента в журнале.
class AgentEvent {
  final DateTime timestamp;
  final AgentEventType type;
  final String title;
  final String? description;
  final String? query;
  final String? sourceUrl;
  final AgentEventStatus status;

  const AgentEvent({
    required this.timestamp,
    required this.type,
    required this.title,
    this.description,
    this.query,
    this.sourceUrl,
    this.status = AgentEventStatus.done,
  });

  AgentEvent asActive() =>
      copyWith(status: AgentEventStatus.active);

  AgentEvent asDone() => copyWith(status: AgentEventStatus.done);

  AgentEvent asError() => copyWith(status: AgentEventStatus.error);

  AgentEvent copyWith({AgentEventStatus? status}) => AgentEvent(
        timestamp: timestamp,
        type: type,
        title: title,
        description: description,
        query: query,
        sourceUrl: sourceUrl,
        status: status ?? this.status,
      );
}

/// Источник в процессе исследования: статус, оценка, причина выбора.
class AgentSource {
  final SearchHit hit;
  final SourceStatus status;
  final double score;
  final String? reason;
  final bool opened;

  const AgentSource({
    required this.hit,
    required this.status,
    this.score = 0,
    this.reason,
    this.opened = false,
  });

  AgentSource copyWith({
    SourceStatus? status,
    double? score,
    String? reason,
    bool? opened,
  }) =>
      AgentSource(
        hit: hit,
        status: status ?? this.status,
        score: score ?? this.score,
        reason: reason ?? this.reason,
        opened: opened ?? this.opened,
      );

  /// Иконка статуса для UI.
  String get statusIcon => switch (status) {
        SourceStatus.used => '✓',
        SourceStatus.found => '○',
        SourceStatus.rejected => '×',
        SourceStatus.conflicting => '!',
        SourceStatus.opened => '◉',
      };
}

/// Полное состояние одного запуска агентного поиска.
class AgentRunState {
  final String query;
  final bool deep;
  final AgentPhase phase;
  final List<AgentEvent> events;
  final List<String> plan;
  final List<String> queries;
  final List<AgentSource> sources;
  final double progress; // 0..1
  final String? error;
  final SearchAnswer? answer;
  final String summary;
  final Duration elapsed;

  const AgentRunState({
    required this.query,
    required this.deep,
    this.phase = AgentPhase.idle,
    this.events = const [],
    this.plan = const [],
    this.queries = const [],
    this.sources = const [],
    this.progress = 0,
    this.error,
    this.answer,
    this.summary = '',
    this.elapsed = Duration.zero,
  });

  AgentRunState copyWith({
    AgentPhase? phase,
    List<AgentEvent>? events,
    List<String>? plan,
    List<String>? queries,
    List<AgentSource>? sources,
    double? progress,
    String? error,
    bool clearError = false,
    SearchAnswer? answer,
    String? summary,
    Duration? elapsed,
  }) =>
      AgentRunState(
        query: query,
        deep: deep,
        phase: phase ?? this.phase,
        events: events ?? this.events,
        plan: plan ?? this.plan,
        queries: queries ?? this.queries,
        sources: sources ?? this.sources,
        progress: progress ?? this.progress,
        error: clearError ? null : (error ?? this.error),
        answer: answer ?? this.answer,
        summary: summary ?? this.summary,
        elapsed: elapsed ?? this.elapsed,
      );
}

/// Мост между сервисом поиска и контроллером состояния: сервис шлёт
/// события процесса, UI подписан на состояние.
class SearchReporter {
  final void Function(AgentPhase phase) onPhase;
  final void Function(AgentEvent event) onEvent;
  final void Function(List<String> plan) onPlan;
  final void Function(String query) onQuery;
  final void Function(AgentSource source) onSource;
  final void Function(double progress) onProgress;

  const SearchReporter({
    required this.onPhase,
    required this.onEvent,
    required this.onPlan,
    required this.onQuery,
    required this.onSource,
    required this.onProgress,
  });

  void phase(AgentPhase p) => onPhase(p);

  void event(
    AgentEventType type,
    String title, {
    String? description,
    String? query,
    String? sourceUrl,
  }) =>
      onEvent(AgentEvent(
        timestamp: DateTime.now(),
        type: type,
        title: title,
        description: description,
        query: query,
        sourceUrl: sourceUrl,
      ));

  void plan(List<String> p) => onPlan(p);

  void query(String q) => onQuery(q);

  void source(AgentSource s) => onSource(s);

  void progress(double v) => onProgress(v);
}

/// Контроллер агентного поиска: запускает [SearchService.ask] или
/// [SearchService.deepResearch] и публикует живой процесс в состояние.
class SearchRunController extends Notifier<AgentRunState> {
  Timer? _ticker;
  DateTime? _startedAt;
  bool _running = false;

  @override
  AgentRunState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _ticker = null;
    });
    return const AgentRunState(
      query: '',
      deep: false,
    );
  }

  bool get isRunning => _running;

  AgentReporterContext _reporter() {
    final self = this;
    return AgentReporterContext(self);
  }

  Future<void> start({required String query, required bool deep}) async {
    if (_running) return;
    final q = query.trim();
    if (q.isEmpty) return;
    _running = true;
    _startedAt = DateTime.now();
    state = AgentRunState(query: q, deep: deep, phase: AgentPhase.analyzing);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_startedAt == null) return;
      state = state.copyWith(elapsed: DateTime.now().difference(_startedAt!));
    });

    final rep = _reporter();
    try {
      final answer = deep
          ? await SearchService.deepResearch(ref, q, reporter: rep.reporter)
          : await SearchService.ask(ref, q, reporter: rep.reporter);
      state = state.copyWith(
        phase: AgentPhase.completed,
        answer: answer,
        progress: 1,
        summary: _buildSummary(),
      );
    } catch (e) {
      state = state.copyWith(
        phase: AgentPhase.failed,
        error: '$e',
      );
    } finally {
      _running = false;
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Сводка для шапки ответа: сколько запросов, источников, открыто,
  /// отброшено, противоречий (раздел 30 спецификации).
  String _buildSummary() {
    final s = state;
    final opened = s.sources.where((x) => x.opened).length;
    final used = s.sources.where((x) => x.status == SourceStatus.used).length;
    final rejected =
        s.sources.where((x) => x.status == SourceStatus.rejected).length;
    final conflicts = s.events
        .where((e) => e.type == AgentEventType.factConflictFound)
        .length;
    final followups = s.events
        .where((e) => e.type == AgentEventType.followUpSearchStarted)
        .length;
    final found = _foundPages(s);
    final sb = StringBuffer('🔎 Исследовал вопрос');
    if (found != null) {
      sb.write('\nНайдено $found веб-страниц');
    }
    if (s.queries.isNotEmpty) {
      sb.write('\nПроверил ${s.queries.length} '
          'поисковых запрос${_plural(s.queries.length)}');
    }
    if (opened > 0 || used > 0) {
      sb.write('\nОткрыл $opened источник${_plural(opened)}, '
          'использовал $used');
    }
    if (rejected > 0) {
      sb.write('\nОтбросил $rejected нерелевантных');
    }
    if (conflicts > 0) {
      sb.write('\nНашёл противоречие между двумя источниками'
          '${followups > 0 ? ' и проверил его дополнительным поиском' : ''}');
    }
    return sb.toString();
  }

  /// Сколько всего страниц найдено поиском (из событий выдачи).
  static int? _foundPages(AgentRunState s) {
    for (final e in s.events.reversed) {
      if (e.type != AgentEventType.searchResultsReceived) continue;
      final m = RegExp(r'Получено (\d+)').firstMatch(e.title);
      if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    }
    return null;
  }

  static String _plural(int n) {
    final m = n % 10;
    final h = n % 100;
    if (m == 1 && h != 11) return '';
    if (m >= 2 && m <= 4 && (h < 12 || h > 14)) return 'а';
    return 'ов';
  }

  void stop() {
    _running = false;
    _ticker?.cancel();
    _ticker = null;
  }

  // ---- Публичные методы обновления состояния (для SearchReporter) ----

  void reportPhase(AgentPhase phase) {
    state = state.copyWith(phase: phase);
  }

  void reportEvent(AgentEvent event) {
    state = state.copyWith(events: [...state.events, event]);
  }

  void reportPlan(List<String> plan) {
    state = state.copyWith(plan: plan);
  }

  void reportQuery(String q) {
    if (!state.queries.contains(q)) {
      state = state.copyWith(queries: [...state.queries, q]);
    }
  }

  void reportSource(AgentSource source) {
    final next = <AgentSource>[];
    var added = false;
    for (final x in state.sources) {
      if (x.hit.url == source.hit.url) {
        next.add(source);
        added = true;
      } else {
        next.add(x);
      }
    }
    if (!added) next.add(source);
    state = state.copyWith(sources: next);
  }

  void reportProgress(double v) {
    state = state.copyWith(progress: v);
  }
}

/// Хелпер-мост: методы репортера, которые дёргают контроллер и обновляют
/// состояние (чтобы репортер не знал о Riverpod).
class AgentReporterContext {
  final SearchRunController controller;

  AgentReporterContext(this.controller);

  void onPhase(AgentPhase phase) => controller.reportPhase(phase);

  void onEvent(AgentEvent event) => controller.reportEvent(event);

  void onPlan(List<String> plan) => controller.reportPlan(plan);

  void onQuery(String q) => controller.reportQuery(q);

  void onSource(AgentSource source) => controller.reportSource(source);

  void onProgress(double v) => controller.reportProgress(v);

  SearchReporter get reporter => SearchReporter(
        onPhase: onPhase,
        onEvent: onEvent,
        onPlan: onPlan,
        onQuery: onQuery,
        onSource: onSource,
        onProgress: onProgress,
      );
}

final searchRunProvider =
    NotifierProvider<SearchRunController, AgentRunState>(
        SearchRunController.new);
