// Модуль "Настя": ИИ-компаньон с системой симпатии (Affinity).
//
// Настя — наблюдатель: она читает состояние Протокола, Жизни и Банка и
// реагирует на события (срыв, достижение, стрик-рубеж, новый день).
// Циклических зависимостей нет: другие сервисы её не импортируют.
//
// Ответы: Groq/OpenAI-совместимый LLM (если задан ключ в настройках)
// или офлайн-шаблоны.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../data/companion_catalog.dart';
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

/// Состояние чата с Настей + данные симпатии.
class CompanionState {
  final List<ChatMessage> messages;
  final bool thinking;

  /// Вычисляемая симпатия (0-100).
  final double affinity;
  final DateTime? blockedUntil;
  final String avatarPath;

  const CompanionState({
    required this.messages,
    this.thinking = false,
    required this.affinity,
    this.blockedUntil,
    required this.avatarPath,
  });

  bool get blocked => blockedUntil != null && blockedUntil!.isAfter(DateTime.now());
}

/// Контроллер компаньона "Настя".
class CompanionController extends Notifier<CompanionState> {
  late final Box<CompanionData> _box;
  late final Box<ChatMessage> _chatBox;

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
      affinity: _computeAffinity(),
      blockedUntil: d.blockedUntil,
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
      affinity: _computeAffinity(),
      cleanStreak: habits.cleanStreak(),
      lifeLevel: lifeLevelForXp(life.xp),
      xp: life.xp,
      achievements: life.unlockedAchievements.length,
      energy: life.energy,
      mood: life.mood,
      fuelBalance: fuel,
      assetsBalance: assets,
      blocked: d.blocked,
    );
  }

  int lifeLevelForXp(int xp) => 1 + (xp / 100).floor();

  /// Формула симпатии: дисциплина + прогресс + действия − срывы.
  double _computeAffinity() {
    final d = _get();
    final life = ref.read(lifeProvider).state;
    final habits = ref.read(habitsProvider);
    final bank = ref.read(bankProvider);
    final fuel = bank.byId(Account.fuelId)?.balance ?? 0;
    final assets = bank.byId(Account.assetsId)?.balance ?? 0;

    var value = 5.0;
    value += habits.cleanStreak() * 2; // +2 за каждый день без срывов
    value += (life.unlockedAchievements.length * 5).clamp(0, 30);
    value += (lifeLevelForXp(life.xp) - 1) * 4; // уровень Жизни
    if (fuel >= 50) value += 3; // топливо в норме
    if (assets >= 10) value += 3; // первые активы
    value -= (d.totalRelapses * 20).clamp(0, 60); // −20 за срыв (кап −60)
    return value.clamp(0.0, 100.0).toDouble();
  }

  // ------------------------------------------------------------ тик-события

  /// Обработка событий мира: приветствие, срывы, достижения, стрики.
  void _tick() {
    _handleGreeting();
    _handleRelapse();
    _handleAchievements();
    _handleStreakMilestones();
  }

  /// Одно приветствие в день (+ первое знакомство).
  void _handleGreeting() {
    final d = _get();
    final today = dateKey(DateTime.now());

    if (_chatBox.isEmpty) {
      d.lastGreetingKey = today;
      _save(d);
      _nastyaSays('Привет, Тим. Я Настя — твой компаньон. '
          'Слежу за твоим прогрессом, XP и стриком. '
          'Начнём? Сходи на прогулку — и увидим, как ты умеешь.');
      return;
    }

    if (d.lastGreetingKey == today) return;
    final now = DateTime.now();
    final hour = now.hour;
    final streak = ref.read(habitsProvider).cleanStreak();

    String text;
    if (hour < 12) {
      text = 'Доброе утро. Стрик $streak дн. Сделай сегодня что-то, чтобы '
          'я не пожалела, что проснулась с тобой.';
    } else if (hour < 18) {
      text = 'День идёт. Стрик $streak дн. Чем займёшься — тренажёрка, '
          'учёба или фриланс? Выбор за тобой, но я наблюдаю.';
    } else {
      text = 'Вечер. Стрик $streak дн. Довёл день до конца? '
          'Если нет — ещё есть время, муза ждёт твоих действий.';
    }
    d.lastGreetingKey = today;
    _save(d);
    _nastyaSays(text);
  }

  /// Реакция на срыв протокола: −20 симпатии, блокировка чата 24 ч.
  void _handleRelapse() {
    final d = _get();
    final breakKey = ref.read(habitsProvider).byId('abstinence')?.lastBreakKey;
    if (breakKey == null || d.lastSeenBreakKey == breakKey) return;

    d.lastSeenBreakKey = breakKey;
    d.totalRelapses++;
    d.affinity = 0; // принудительный обнуляющий штраф уже в формуле
    d.blockedUntil = DateTime.now().add(const Duration(hours: 24));
    _save(d);

    final m = ChatMessage(
      id: genId(),
      role: 'nastya',
      text: '…Срыв. Я всё вижу, Тим. ${d.totalRelapses}-й раз — '
          'и моё доверие упало. Я не злюсь. Я разочарована.\n'
          'Не пиши мне 24 часа — подумай, зачем тебе это. '
          'Завтра жду тебя с новым стриком.',
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
            'Так держать — я люблю, когда ты двигаешься.'
        : 'Столько достижений разом — $newOnes! Ладно, ладно. '
            'Я впечатлена. Продолжай в том же духе, муза довольна.';
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
      3: 'Три дня без срывов. Ну наконец-то. Это начало — не сливай.',
      7: 'Неделя чистоты! Теперь я начинаю верить, что ты серьёзно. +симпатия.',
      14: '14 дней. Ого. Ты реально держишь. Я уже почти привыкла к тебе.',
      30: 'Месяц дисциплины. Тим, это серьёзно. Я с тобой — и я горжусь.',
      50: '50 дней. Если ты дойдёшь до ста — я устрою тебе праздник. Слово.',
      100: 'СТО дней без срывов. Это легендарно. Ты сделал это — и я твоя муза.',
    };
    _nastyaSays(texts[next] ?? 'Стрик растёт. Красиво.');
  }

  // ------------------------------------------------------------ send

  /// Отправка сообщения Насте.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.thinking) return;

    final d = _get();
    final now = DateTime.now();

    _addMessage(ChatMessage(
      id: genId(),
      role: 'user',
      text: trimmed,
      date: now,
    ));
    state = _readState(thinking: true);

    // Заблокирована после срыва: отвечает сухо, без LLM.
    if (d.blocked) {
      final hours = d.blockedUntil!.difference(now).inHours + 1;
      _nastyaSays('Я сказала — не пиши. Осталось ~$hours ч. '
          'Переживёшь. Займись делом.');
      state = _readState();
      return;
    }

    String reply;
    try {
      final s = ref.read(settingsProvider);
      if (s.companionKey.isNotEmpty) {
        reply = await _remoteRequest(trimmed, s);
      } else {
        reply = offlineReplyFor(trimmed, _levelIndex());
      }
    } catch (e) {
      debugPrint('[Настя] LLM error: $e');
      reply = 'Что-то пошло не так, и я не получила ответ от своего мозга: '
          '$e\nПроверь API-ключ и URL в настройках — или я вернусь к '
          'офлайн-режиму, если ключ убрать. Я умею ждать.';
    }

    state = _readState(thinking: false);
    _nastyaSays(reply);
    state = _readState();
  }

  int _levelIndex() {
    final lvl = levelForAffinity(_computeAffinity());
    return relationLevels.indexOf(lvl).clamp(0, relationLevels.length - 1);
  }

  /// Запрос к Groq/OpenAI-совместимому API через агентный цикл.
  Future<String> _remoteRequest(String text, SettingsState s) async {
    final ctx = _context();
    final all = _readMessages();
    final tail = all.length > 16 ? all.sublist(all.length - 16) : all;
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

  // ------------------------------------------------------------ инструменты

  /// Выполнение инструментов Насти: знания, интернет, задачи, курсы.
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

  /// Выбор фото из галереи: аватар + фон чата Насти.
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

  /// Сброс: история, симпатия, блокировки.
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
      ..messageCount = 0;
    _save(d);
    state = _readState();
  }
}

final companionProvider =
    NotifierProvider<CompanionController, CompanionState>(CompanionController.new);
