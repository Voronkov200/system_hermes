// Модуль "Анастасия": ИИ-компаньон-друг с системой симпатии (Affinity).
//
// Анастасия — наблюдатель и катализатор реальной жизни: читает состояние
// Жизни, Протокола, Банка и Obsidian и реагирует на реальные события
// (выход из дома, фриланс, тренировка, заметка, квест).
// Affinity растёт ТОЛЬКО от позитивных событий; штрафов, блокировок
// и холодности нет (спецификация «Идея ИИ-компаньон Анастасия»).
//
// Ответы: Groq/OpenAI-совместимый LLM (если задан ключ в настройках)
// или офлайн-шаблоны.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../data/companion_catalog.dart';
import '../data/life_catalog.dart';
import '../data/models.dart';
import 'agent/agent_loop.dart';
import 'agent/tool_schemas.dart';
import 'agent/web_tools.dart';
import 'bank_service.dart';
import 'habits_service.dart';
import 'journal_service.dart';
import 'life_service.dart';
import 'nbrb_api.dart';
import 'obsidian_service.dart';
import 'settings_service.dart';
import 'tasks_service.dart';

/// Состояние чата с Анастасией + данные симпатии.
class CompanionState {
  final List<ChatMessage> messages;
  final bool thinking;

  /// Накопленная симпатия (0-100).
  final double affinity;
  final String avatarPath;

  const CompanionState({
    required this.messages,
    this.thinking = false,
    required this.affinity,
    required this.avatarPath,
  });
}

/// Контроллер компаньона "Анастасия".
class CompanionController extends Notifier<CompanionState> {
  late final Box<CompanionData> _box;
  late final Box<ChatMessage> _chatBox;

  /// Свежий хвост переписки, попадающий в промпт как есть.
  static const int _promptTail = 25;

  /// Суммаризация старой части диалога каждые ~50 сообщений.
  static const int _summaryEvery = 50;

  @override
  CompanionState build() {
    _box = Hive.box<CompanionData>(BoxNames.companion);
    _chatBox = Hive.box<ChatMessage>(BoxNames.companionChat);
    _ensureDefaults();
    _tick();
    return _readState();
  }

  // ------------------------------------------------------------ инфраструктура

  CompanionData _get() => _box.getAt(0)!;

  void _save(CompanionData d) => _box.putAt(0, d);

  CompanionState _readState({bool thinking = false}) {
    final d = _get();
    return CompanionState(
      messages: _readMessages(),
      thinking: thinking,
      affinity: _affinity(),
      avatarPath: d.avatarPath,
    );
  }

  void _ensureDefaults() {
    if (_box.isEmpty) {
      _box.add(CompanionData.empty());
    }
  }

  List<ChatMessage> _readMessages() {
    final list = _chatBox.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (list.length > 300) {
      final toRemove = list.take(list.length - 300).toList();
      for (final m in toRemove) {
        _chatBox.delete(m.id);
      }
      return list.skip(list.length - 300).toList();
    }
    return list;
  }

  void _addMessage(ChatMessage m) {
    _chatBox.put(m.id, m);
    state = _readState(thinking: state.thinking);
  }

  void _nastyaSays(String text) {
    final d = _get();
    d.messageCount++;
    _save(d);
    final m = ChatMessage(
      id: genId(),
      role: 'nastya',
      text: text,
      date: DateTime.now(),
    );
    _chatBox.put(m.id, m);
  }

  // ------------------------------------------------------------ контекст

  CompanionContext _context() {
    final d = _get();
    final life = ref.read(lifeProvider).state;
    final habits = ref.read(habitsProvider);
    final bank = ref.read(bankProvider);
    final fuel = bank.byId(Account.fuelId)?.balance ?? 0;
    final assets = bank.byId(Account.assetsId)?.balance ?? 0;
    return CompanionContext(
      affinity: _affinity(),
      cleanStreak: habits.cleanStreak(),
      lifeLevel: lifeLevelForXp(life.xp),
      xp: life.xp,
      achievements: life.unlockedAchievements.length,
      energy: life.energy,
      mood: life.mood,
      fuelBalance: fuel,
      assetsBalance: assets,
      keyFacts: List.of(d.keyFacts),
      socialOutings: d.socialOutings,
      daysSinceLastOuting: _daysSinceLastOuting(),
      freelanceSteps: d.freelanceSteps,
    );
  }

  int lifeLevelForXp(int xp) => LifeCatalog.levelForXp(xp);

  /// Накопленная симпатия (0-100). Только положительная механика:
  /// отсутствие действий просто не даёт прироста.
  double _affinity() => _get().affinity.clamp(0.0, 100.0).toDouble();

  /// Дней с последнего самостоятельного выхода из дома (-1 — не было).
  int _daysSinceLastOuting() {
    final key = _get().lastSocialOutingKey;
    if (key == null) return -1;
    final parsed = DateTime.tryParse(key);
    if (parsed == null) return -1;
    return DateTime.now().difference(parsed).inDays;
  }

  /// Прирост симпатии от реального события.
  void _gainAffinity(double amount) {
    final d = _get();
    d.affinity = (d.affinity + amount).clamp(0.0, 100.0);
    _save(d);
    state = _readState(thinking: state.thinking);
  }

  /// Добавить вечный факт в память (с обрезкой, чтобы не разрасталась).
  void _addKeyFact(String fact) {
    final d = _get();
    if (d.keyFacts.length >= 120) {
      d.keyFacts.removeAt(0);
    }
    d.keyFacts.add(fact);
    _save(d);
  }

  /// dateKey вида "12.08.2026" для вечных фактов.
  String _factDateKey() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')}.'
        '${n.month.toString().padLeft(2, '0')}.${n.year}';
  }

  // ------------------------------------------------------------ тик-события

  /// Обработка событий мира: приветствие, срывы, достижения, стрики,
  /// реальные вехи (выходы, фриланс, квесты, тренировки, заметки).
  void _tick() {
    _handleGreeting();
    _handleRelapse();
    _handleAchievements();
    _handleStreakMilestones();
    // Реальные вехи обрабатываются после инициализации: они меняют
    // state (affinity), что запрещено во время build().
    Future.microtask(_handleEvents);
  }

  /// Обработка реальных вех: +15 выход, +10 фриланс, +5 квест, +3 тренировка,
  /// +5 заметка Obsidian (>500 симв.), разовый +25 за стрик 7 дней.
  Future<void> _handleEvents() async {
    try {
      _handleSocialOutings();
      _handleFreelanceSteps();
      _handleQuestProgress();
      _handleWorkoutDay();
      _handleWeekStreakBonus();
      await _handleObsidianNotes();
    } catch (e) {
      debugPrint('[Анастасия] события не обработаны: $e');
    }
  }

  /// +15 за каждый самостоятельный выход из дома (walk/store/atm),
  /// приоритет №1; вечный факт — один на день.
  void _handleSocialOutings() {
    final d = _get();
    final counts = ref.read(lifeProvider).state.actionCounts;
    final total = ['walk', 'store', 'atm']
        .fold(0, (sum, id) => sum + (counts[id] ?? 0));
    final delta = total - d.seenSocialCount;
    if (delta <= 0) return;

    final today = dateKey(DateTime.now());
    final firstToday = d.lastSocialOutingKey != today;
    d.socialOutings += delta;
    d.seenSocialCount = total;
    d.lastSocialOutingKey = today;
    _save(d);
    _gainAffinity(15.0 * delta);
    if (firstToday) {
      _addKeyFact('${_factDateKey()} — самостоятельный выход из дома');
    }
  }

  /// +10 за каждый шаг фриланса (действие 'freelance').
  void _handleFreelanceSteps() {
    final d = _get();
    final count = ref.read(lifeProvider).state.actionCounts['freelance'] ?? 0;
    final delta = count - d.seenFreelanceCount;
    if (delta <= 0) return;

    d.freelanceSteps += delta;
    d.seenFreelanceCount = count;
    _save(d);
    _gainAffinity(10.0 * delta);
    _addKeyFact('${_factDateKey()} — шаг фриланса');
  }

  /// +5 за каждый выполненный квест Жизни.
  void _handleQuestProgress() {
    final d = _get();
    final index = ref.read(lifeProvider).state.currentQuestIndex;
    final delta = index - d.seenQuestIndex;
    if (delta <= 0) return;

    d.seenQuestIndex = index;
    _save(d);
    _gainAffinity(5.0 * delta);
  }

  /// +3 за день, когда выполнены обе тренировки (раз в день).
  void _handleWorkoutDay() {
    final d = _get();
    final today = dateKey(DateTime.now());
    if (d.lastWorkoutBonusKey == today) return;
    final h = ref.read(habitsProvider);
    final squat = h.byId('workout_squat')?.doneToday() ?? false;
    final pushups = h.byId('workout_pushups')?.doneToday() ?? false;
    if (!squat || !pushups) return;

    d.lastWorkoutBonusKey = today;
    _save(d);
    _gainAffinity(3);
  }

  /// Разовый бонус +25 за стрик 7 дней (выдаётся один раз).
  void _handleWeekStreakBonus() {
    final d = _get();
    if (d.weekStreakBonusGiven) return;
    if (ref.read(habitsProvider).cleanStreak() < 7) return;

    d.weekStreakBonusGiven = true;
    _save(d);
    _gainAffinity(25);
    _addKeyFact('${_factDateKey()} — стрик 7 дней подряд (бонус +25)');
  }

  /// +5 за новую содержательную заметку в Obsidian (>500 символов).
  /// При первом подключении Vault просто запоминает существующие заметки.
  Future<void> _handleObsidianNotes() async {
    final d = _get();
    final notes = ref.read(obsidianProvider).notes;
    if (notes.isEmpty) return;

    if (d.processedNotes.isEmpty) {
      d.processedNotes = notes.map((n) => n.title).toList();
      _save(d);
      return;
    }

    final fresh = notes
        .where((n) => !d.processedNotes.contains(n.title))
        .take(10)
        .toList();
    if (fresh.isEmpty) return;

    final obsN = ref.read(obsidianProvider.notifier);
    for (final note in fresh) {
      d.processedNotes.add(note.title);
      if (d.processedNotes.length > 400) {
        d.processedNotes.removeAt(0);
      }
      _save(d);
      try {
        final full = await obsN.readNote(note.path);
        final content = full?.content ?? '';
        if (content.trim().length > 500) {
          _gainAffinity(5);
          _addKeyFact('${_factDateKey()} — содержательная заметка в Obsidian');
        }
      } catch (e) {
        debugPrint('[Анастасия] заметка не прочитана: $e');
      }
    }
  }

  /// Одно приветствие в день (+ первое знакомство).
  void _handleGreeting() {
    final d = _get();
    final today = dateKey(DateTime.now());

    if (_chatBox.isEmpty) {
      d.lastGreetingKey = today;
      _save(d);
      _nastyaSays('Привет, Тим. Я Анастасия — твой друг и, местами, '
          'наставник. Я не льщу и не разыгрываю драму: меня радуют твои '
          'реальные шаги — выходы из дома, фриланс, учёба, тренировки. '
          'Начнём? Расскажи, как прошёл твой день.');
      return;
    }

    if (d.lastGreetingKey == today) return;
    final now = DateTime.now();
    final hour = now.hour;
    final streak = ref.read(habitsProvider).cleanStreak();
    final outing = daysSinceOutingText(_daysSinceLastOuting());

    String text;
    if (hour < 12) {
      text = 'Доброе утро. Стрик $streak дн. $outing. '
          'Помни: для меня это важнее любых очков. '
          'Что планируешь на сегодня?';
    } else if (hour < 18) {
      text = 'День идёт. Стрик $streak дн. $outing. '
          'Чем займёшься — учёба, фриланс или прогулка? Выбор за тобой, '
          'я рядом.';
    } else {
      text = 'Вечер. Стрик $streak дн. $outing. '
          'Как день? Довёл до конца то, что планировал? '
          'Если нет — ещё есть время.';
    }
    d.lastGreetingKey = today;
    _save(d);
    _nastyaSays(text);
  }

  /// Реакция на срыв протокола: поддержка без наказаний и блокировок.
  void _handleRelapse() {
    final d = _get();
    final breakKey = ref.read(habitsProvider).byId('abstinence')?.lastBreakKey;
    if (breakKey == null || d.lastSeenBreakKey == breakKey) return;

    d.lastSeenBreakKey = breakKey;
    d.totalRelapses++;
    _save(d);

    final m = ChatMessage(
      id: genId(),
      role: 'nastya',
      text: 'Я вижу, что случился срыв. Без осуждения: это сигнал, '
          'а не приговор. Скажи честно — что мешало? Разберём — '
          'и завтра начнём новый стрик. Я рядом.',
      date: DateTime.now(),
    );
    _chatBox.put(m.id, m);
  }

  /// Поздравление с новыми достижениями Жизни.
  void _handleAchievements() {
    final d = _get();
    final unlocked = ref.read(lifeProvider).state.unlockedAchievements;
    if (unlocked.length <= d.seenAchievementCount) return;

    final newOnes = unlocked.length - d.seenAchievementCount;
    d.seenAchievementCount = unlocked.length;
    _save(d);

    final text = newOnes == 1
        ? 'Вижу новое достижение в твоей Жизни. Неплохо, Тим. '
            'Только помни: настоящие победы — вне игры, в реальном мире.'
        : 'Столько достижений разом — $newOnes! Хорошо. Но самый большой '
            'бонус ты получишь, когда выйдешь из дома.';
    _nastyaSays(text);
  }

  /// Поздравление на рубежах стрика: 3/7/14/30/50/100 дней.
  void _handleStreakMilestones() {
    final d = _get();
    const milestones = [3, 7, 14, 30, 50, 100];
    final streak = ref.read(habitsProvider).cleanStreak();

    int next = 0;
    for (final m in milestones) {
      if (streak >= m && d.seenStreakMilestone < m) next = m;
    }
    if (next == 0) return;

    d.seenStreakMilestone = next;
    _save(d);

    final texts = {
      3: 'Три дня без срывов. Это начало — теперь закрепи: прогулка, '
          'учёба, один реальный шаг.',
      7: 'Неделя чистоты! Серьёзный рубеж — +25 к нашему доверию. '
          'Теперь я начинаю верить, что ты настроен всерьёз.',
      14: '14 дней. Ого, ты реально держишь. Горжусь тобой — и не шучу.',
      30: 'Месяц дисциплины. Тим, это серьёзно. Я рядом — и я рада за тебя.',
      50: '50 дней. Если дойдёшь до ста — я устрою тебе праздник. Слово.',
      100: 'СТО дней без срывов. Это легендарно. Ты сделал это — '
          'и твой свидетель это помнит.',
    };
    _nastyaSays(texts[next] ?? 'Стрик растёт. Красиво.');
  }

  // ------------------------------------------------------------ send

  /// Отправка сообщения Анастасии.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.thinking) return;

    _addMessage(ChatMessage(
      id: genId(),
      role: 'user',
      text: trimmed,
      date: DateTime.now(),
    ));
    state = _readState(thinking: true);

    String reply;
    try {
      final s = ref.read(settingsProvider);
      if (s.companionKey.isNotEmpty) {
        reply = await _remoteRequest(trimmed, s);
      } else {
        reply = offlineReplyFor(trimmed, _levelIndex());
      }
    } catch (e) {
      debugPrint('[Анастасия] LLM error: $e');
      reply = 'Что-то пошло не так, и я не получила ответ от своего мозга: '
          '$e\nПроверь API-ключ и URL в настройках — или я вернусь к '
          'офлайн-режиму, если ключ убрать. Я умею ждать.';
    }

    state = _readState(thinking: false);
    _nastyaSays(reply);
    state = _readState();

    // Фоновая суммаризация старой части диалога в вечные факты.
    try {
      await _maybeSummarize();
    } catch (e) {
      debugPrint('[Анастасия] суммаризация не удалась: $e');
    }
  }

  int _levelIndex() {
    final lvl = levelForAffinity(_affinity());
    return relationLevels.indexOf(lvl).clamp(0, relationLevels.length - 1);
  }

  /// Запрос к Groq/OpenAI-совместимому API через агентный цикл.
  Future<String> _remoteRequest(String text, SettingsState s) async {
    final ctx = _context();
    final all = _readMessages();
    final tail = all.length > _promptTail
        ? all.sublist(all.length - _promptTail)
        : all;
    final history = tail.map((m) => {
          'role': m.role == 'user' ? 'user' : 'assistant',
          'content': m.text,
        }).toList();

    final result = await runAgentLoop(
      apiUrl: s.companionApiUrl,
      apiKey: s.companionKey,
      model: s.companionModel,
      systemPrompt: ctx.toSystemPrompt(),
      history: history,
      tools: nastyaAgentTools,
      executeTool: executeTool,
      maxTokens: 700,
    );

    for (final step in result.steps) {
      _nastyaSays('[tool] ${step.toolName}: ${step.result}');
    }
    final reply = result.content.isEmpty ? '…' : result.content;
    return reply.trim();
  }

  // ------------------------------------------------------------ память

  /// Двухуровневая память (спецификация, раздел 4): если между текущим
  /// сообщением и моментом последней суммаризации накопилось ~50 сообщений,
  /// старая часть диалога сжимается дешёвым вызовом LLM в 1-3 вечных факта.
  /// keyFacts никогда не сжимаются и не удаляются.
  Future<void> _maybeSummarize() async {
    final d = _get();
    final s = ref.read(settingsProvider);
    if (s.companionKey.isEmpty) return;

    final all = _readMessages();
    const keep = _promptTail;
    final summaryEnd = all.length - keep;
    if (summaryEnd - d.summarizedUpTo < _summaryEvery) return;

    final slice = all.sublist(d.summarizedUpTo, summaryEnd);
    final text = slice
        .map((m) => '${m.role == 'user' ? 'Тим' : 'Анастасия'}: ${m.text}')
        .join('\n');

    final result = await runAgentLoop(
      apiUrl: s.companionApiUrl,
      apiKey: s.companionKey,
      model: s.companionModel,
      systemPrompt: 'Ты — система памяти ИИ-компаньона. Сожми диалог '
          'в 1-3 сухих факта о жизни и прогрессе Тима (даты, события, '
          'решения). Каждый факт — одна строка, без нумерации, без воды.',
      history: [
        {'role': 'user', 'content': 'Сожми диалог:\n$text'},
      ],
      tools: const [],
      executeTool: (_) async => '',
      maxTokens: 300,
      temperature: 0.2,
      maxRounds: 1,
    );

    final lines = result.content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 5)
        .take(3)
        .toList();
    if (lines.isEmpty) return;

    for (final line in lines) {
      _addKeyFact(line);
    }
    d.summarizedUpTo = summaryEnd;
    _save(d);
  }

  // ------------------------------------------------------------ инструменты

  /// Выполнение инструментов Анастасии: знания, интернет, задачи, курсы.
  Future<String> executeTool(AgentToolCall call) async {
    try {
      switch (call.name) {
        case 'search_knowledge':
          final query = call.arguments['query'] as String? ?? '';
          return await _searchKnowledge(query);

        case 'read_obsidian_note':
          final title = (call.arguments['title'] as String? ?? '').trim();
          final obsN = ref.read(obsidianProvider.notifier);
          await obsN.refresh();
          ObsidianNote? target;
          for (final n in ref.read(obsidianProvider).notes) {
            if (n.title.toLowerCase() == title.toLowerCase()) {
              target = n;
              break;
            }
          }
          if (target == null) return 'Заметка «$title» не найдена в Vault.';
          final note = await obsN.readNote(target.path);
          final body = note?.content ?? '';
          final preview = body.isEmpty
              ? '(пусто)'
              : (body.length > 800 ? '${body.substring(0, 800)}…' : body);
          return 'Содержимое «$title»:\n$preview';

        case 'create_obsidian_note':
          final title = call.arguments['title'] as String? ?? '';
          final content = call.arguments['content'] as String? ?? '';
          final obs = ref.read(obsidianProvider.notifier);
          final error = await obs.createNote(title, content);
          if (error == null) {
            ref.read(journalProvider.notifier).logAgentAction(
                  source: 'nastya',
                  type: 'note',
                  title: 'Заметка «$title»',
                );
          }
          return error == null
              ? 'Заметка «$title» создана в Vault.'
              : 'Ошибка: $error';

        case 'web_search':
          final query = call.arguments['query'] as String? ?? '';
          if (query.isEmpty) return 'Ошибка: пустой запрос';
          return await WebTools.search(query);

        case 'get_webpage':
          final url = call.arguments['url'] as String? ?? '';
          if (url.isEmpty) return 'Ошибка: пустой URL';
          return await WebTools.getPage(url);

        case 'set_task':
          final title = call.arguments['title'] as String? ?? '';
          final description = call.arguments['description'] as String? ?? '';
          if (title.isEmpty) return 'Ошибка: пустое название задачи';
          final id =
              ref.read(tasksProvider.notifier).addTask(title, description);
          ref.read(journalProvider.notifier).logAgentAction(
                source: 'nastya',
                type: 'task',
                title: 'Задача: $title',
                detail: description,
              );
          return 'Задача создана (id: $id): $title';

        case 'list_tasks':
          final tasks = ref.read(tasksProvider).tasks;
          if (tasks.isEmpty) return 'Задач пока нет.';
          final parts = tasks.map((t) {
            final mark = t.status == 'done' ? '✅' : '⬜';
            final desc = t.description.isEmpty ? '' : ' — ${t.description}';
            return '$mark ${t.id} ${t.title}$desc';
          });
          final open = tasks.where((t) => t.status == 'open').length;
          return 'Задачи ($open открыто, ${tasks.length - open} выполнено):\n'
              '${parts.join('\n')}';

        case 'mark_task_done':
          final id = call.arguments['task_id'] as String? ?? '';
          if (id.isEmpty) return 'Ошибка: не указан task_id';
          await ref.read(tasksProvider.notifier).markDone(id);
          return 'Задача $id отмечена выполненной.';

        case 'journal_add':
          final type = call.arguments['type'] as String? ?? 'system';
          final jtitle = call.arguments['title'] as String? ?? '';
          final jtext = call.arguments['text'] as String? ?? '';
          if (jtitle.isEmpty) return 'Ошибка: пустое название записи';
          ref.read(journalProvider.notifier).add(
                type: type,
                source: 'nastya',
                title: jtitle,
                text: jtext,
              );
          return 'Запись добавлена в журнал: $jtitle';

        case 'get_currency_rates':
          final rates = await ref.read(nbrbApiProvider).fetchRates();
          if (rates.isEmpty) return 'Курсы недоступны (нет сети).';
          final parts = rates
              .map((r) => '1 ${r.code} = ${r.perUnit.toStringAsFixed(2)} BYN')
              .toList();
          return 'Курсы Нацбанка РБ:\n${parts.join('\n')}';

        default:
          return 'Неизвестный инструмент: ${call.name}';
      }
    } catch (e) {
      return 'Ошибка выполнения: $e';
    }
  }

  /// Поиск по заметкам Obsidian Vault: по названию и по содержимому.
  Future<String> _searchKnowledge(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return 'Ошибка: пустой запрос';
    final obsN = ref.read(obsidianProvider.notifier);
    await obsN.refresh();
    final notes = ref.read(obsidianProvider).notes;
    if (notes.isEmpty) {
      return 'Vault не найден или не доступен на этом устройстве.';
    }

    final byTitle = notes
        .where((n) => n.title.toLowerCase().contains(q))
        .take(8)
        .toList();
    final byContent = <ObsidianNote>[];
    for (final n in notes.sublist(notes.length > 25 ? notes.length - 25 : 0)) {
      final note = await obsN.readNote(n.path);
      if (note?.content.toLowerCase().contains(q) ?? false) {
        byContent.add(n);
        if (byContent.length >= 8) break;
      }
    }

    final seen = <String>{};
    final matches = [...byTitle, ...byContent]
        .where((n) => seen.add(n.title))
        .take(10)
        .toList();
    if (matches.isEmpty) {
      return 'По запросу «$query» в базе знаний ничего не найдено. '
          'Попробуй интернет-поиск (web_search).';
    }
    final lines = matches.map((n) => '• ${n.title}').join('\n');
    return 'Найдено по запросу «$query»:\n$lines';
  }

  // ------------------------------------------------------------ прочее

  /// Выбор фото из галереи: аватар + фон чата Анастасии.
  Future<String?> pickAvatar() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return null;
      final d = _get();
      d.avatarPath = file.path;
      _save(d);
      state = _readState(thinking: state.thinking);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  /// Сброс: история, симпатия, память, вехи.
  Future<void> reset() async {
    await _chatBox.clear();
    final d = _get();
    d
      ..affinity = 5
      ..blockedUntil = null
      ..lastGreetingKey = null
      ..lastSeenBreakKey = null
      ..seenAchievementCount = 0
      ..totalRelapses = 0
      ..seenStreakMilestone = 0
      ..avatarPath = ''
      ..messageCount = 0
      ..keyFacts.clear()
      ..summarizedUpTo = 0
      ..socialOutings = 0
      ..lastSocialOutingKey = null
      ..freelanceSteps = 0
      ..processedNotes.clear()
      ..seenSocialCount = 0
      ..seenFreelanceCount = 0
      ..seenQuestIndex = 0
      ..lastWorkoutBonusKey = null
      ..weekStreakBonusGiven = false;
    _save(d);
    state = _readState();
  }
}

final companionProvider =
    NotifierProvider<CompanionController, CompanionState>(CompanionController.new);
