// Модуль "Hermes Agent Interface": чат-хаб с Tool Calling.
//
// Режимы работы:
//  - Remote: если задан hermesUrl в настройках, сообщения уходят на сервер
//    Hermes Agent (POST {message}), ответ может содержать tool_calls.
//  - Offline: локальный отклик с демонстрацией тех же инструментов.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/persona.dart';
import 'bank_service.dart';
import 'github_api.dart';
import 'habits_service.dart';
import 'health_service.dart';
import 'nbrb_api.dart';
import 'obsidian_service.dart';
import 'settings_service.dart';
import 'tasks_service.dart';
import 'agent/agent_loop.dart';
import 'agent/file_tools.dart';
import 'agent/tool_schemas.dart';
import 'agent/web_tools.dart';
import 'journal_service.dart';

/// Состояние чата.
class ChatState {
  final List<ChatMessage> messages;
  final bool thinking;

  /// Запрос фото-верификации от Hermes (пока не отправлено).
  final String? pendingPhotoTask;
  final String? pendingPhotoDescription;

  const ChatState({
    required this.messages,
    this.thinking = false,
    this.pendingPhotoTask,
    this.pendingPhotoDescription,
  });
}

/// Контроллер чата с Hermes.
class ChatController extends Notifier<ChatState> {
  late final Box<ChatMessage> _box;

  @override
  ChatState build() {
    _box = Hive.box<ChatMessage>(BoxNames.chat);
    if (_box.isEmpty) {
      final welcomeId = genId();
      _box.put(welcomeId, ChatMessage(
        id: welcomeId,
        role: 'hermes',
        text: 'HERMES на связи. Я твой ассистент и учебный наставник.\n'
            'Помогаю: разбирать учебники и делать конспекты, искать информацию, '
            'составлять задачи в модуле «План», искать и создавать документы.\n'
            'Примеры: «разбери параграф по истории», «найди информацию о …», '
            '«составь задачи на неделю по математике», «сделай конспект по физике».',
        date: DateTime.now(),
      ));
    }
    return ChatState(messages: _readMessages());
  }

  List<ChatMessage> _readMessages() {
    final list = _box.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (list.length > 200) {
      // оставляем последние 200 сообщений
      final toRemove = list.take(list.length - 200).toList();
      for (final m in toRemove) {
        _box.delete(m.id);
      }
      return list.skip(list.length - 200).toList();
    }
    return list;
  }

  void _add(ChatMessage m) {
    _box.put(m.id, m);
    state = ChatState(
      messages: _readMessages(),
      thinking: state.thinking,
      pendingPhotoTask: state.pendingPhotoTask,
      pendingPhotoDescription: state.pendingPhotoDescription,
    );
  }

  void _setState({
    bool? thinking,
    String? photoTask,
    String? photoDesc,
    bool clearPhoto = false,
  }) {
    state = ChatState(
      messages: _readMessages(),
      thinking: thinking ?? state.thinking,
      pendingPhotoTask:
          clearPhoto ? null : (photoTask ?? state.pendingPhotoTask),
      pendingPhotoDescription: clearPhoto
          ? null
          : (photoDesc ?? state.pendingPhotoDescription),
    );
  }

  // ------------------------------------------------------------- send

  /// Отправка сообщения пользователя.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.thinking) return;

    _add(ChatMessage(
      id: genId(),
      role: 'user',
      text: trimmed,
      date: DateTime.now(),
    ));
    _setState(thinking: true);

    final s = ref.read(settingsProvider);
    String reply;
    try {
      if (s.usesHermesServer) {
        reply = await _remoteRequest(trimmed, s);
      } else if (s.usesDirectLlm) {
        reply = await _llmRequest(trimmed, s);
      } else {
        reply = await _offlineRequest(trimmed);
      }
    } catch (e) {
      debugPrint('[Hermes] LLM error: $e');
      final msg = e.toString();
      final low = msg.toLowerCase();
      reply = (msg.contains('401') || msg.contains('403') || low.contains('ключ') || low.contains('api key'))
          ? 'Ошибка API-ключа: проверь его в Настройках → подключение модели '
              '(кнопка «Проверить»). Ключ должен быть от b.ai, а не от Groq.'
          : 'Ошибка соединения: $msg\n\n'
              'Проверь интернет и URL модели в настройках (или выбери «офлайн»).';
    }

    _setState(thinking: false);
    _add(ChatMessage(
      id: genId(),
      role: 'hermes',
      text: reply,
      date: DateTime.now(),
    ));
  }

  /// Отправка фото для верификации.
  Future<void> pickAndSendPhoto() async {
    final task = state.pendingPhotoTask;
    if (task == null) return;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      _add(ChatMessage(
        id: genId(),
        role: 'user',
        text: 'Фото для верификации задачи «$task»',
        date: DateTime.now(),
        toolName: 'request_photo_verification',
        toolStatus: 'ok',
        imagePath: file.path,
      ));
      _setState(clearPhoto: true);
      _add(ChatMessage(
        id: genId(),
        role: 'hermes',
        text: 'Фото получено и сохранено. После подключения Vision AI '
            'на сервере Hermes оно будет проанализировано автоматически.',
        date: DateTime.now(),
      ));
    } catch (e) {
      _add(ChatMessage(
        id: genId(),
        role: 'system',
        text: 'Не удалось выбрать фото: $e',
        date: DateTime.now(),
      ));
    }
  }

  // ----------------------------------------------------------- remote

  Future<String> _remoteRequest(String text, SettingsState s) async {
    final res = await http
        .post(
          Uri.parse(s.hermesUrl),
          headers: {
            'Content-Type': 'application/json',
            if (s.hermesApiKey.isNotEmpty)
              'Authorization': 'Bearer ${s.hermesApiKey}',
          },
          body: jsonEncode({'message': text, 'user': 'tim'}),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

    // Выполнение Tool Calling команд от сервера.
    final rawTools = data['tool_calls'];
    if (rawTools is List) {
      for (final raw in rawTools) {
        if (raw is! Map) continue;
        final call = AgentToolCall(
          (raw['name'] as String?) ?? '',
          ((raw['arguments'] as Map?) ?? {}).cast<String, dynamic>(),
        );
        final result = await executeTool(call);
        _add(ChatMessage(
          id: genId(),
          role: 'system',
          text: '[tool] ${call.name}: $result',
          date: DateTime.now(),
          toolName: call.name,
          toolStatus: result.startsWith('Ошибка') ? 'error' : 'ok',
        ));
      }
    }
    return (data['reply'] as String?) ??
        'Hermes Agent ответил без текста.';
  }

  // ------------------------------------------------------- llm (openai-совм.)

  /// Ответ через OpenAI-совместимый LLM с агентным циклом (function calling).
  Future<String> _llmRequest(String text, SettingsState s) async {
    final apiKey = s.llmKey;
    if (apiKey.isEmpty) {
      return 'API-ключ B.ai не вставлен. Открой Настройки → подключение модели, '
          'вставь ключ и нажми «Проверить».';
    }
    final bank = ref.read(bankProvider);
    final habits = ref.read(habitsProvider);
    final general = bank.generalAccount?.balance ?? 0;
    final cardsByn =
        bank.totalByn(rates: NbrbApi.bundledRates) - general;

    final system = buildHermesSystemPrompt(
      generalBalance: general,
      cardsBynEquivalent: cardsByn < 0 ? 0 : cardsByn,
      trainingStreak: habits.trainingStreak(),
    );

    final all = _readMessages();
    final tail = all.length > 16 ? all.sublist(all.length - 16) : all;
    final history = tail
        .where((m) => m.role != 'system')
        .map((m) => {
              'role': m.role == 'user' ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();

    final result = await runAgentLoop(
      apiUrl: s.hermesLlmUrl,
      apiKey: apiKey,
      model: s.hermesLlmModel,
      systemPrompt: system,
      history: history,
      tools: hermesAgentTools,
      executeTool: executeTool,
      maxTokens: 2048,
    );

    for (final step in result.steps) {
      _add(ChatMessage(
        id: genId(),
        role: 'system',
        text: '[tool] ${step.toolName}: ${step.result}',
        date: DateTime.now(),
        toolName: step.toolName,
        toolStatus: step.result.startsWith('Ошибка') ? 'error' : 'ok',
      ));
    }
    final reply = result.content.isEmpty ? 'Готово. Что дальше?' : result.content;
    return reply.trim();
  }

  // ---------------------------------------------------------- offline

  Future<String> _offlineRequest(String text) async {
    final lower = text.toLowerCase();

    if (lower.contains('заметк')) {
      final rest = text.replaceFirst(RegExp(r'(создай|создать)?\s*заметк\w*\s*[:,-]?\s*', caseSensitive: false), '');
      if (rest.isEmpty) {
        return 'Формат: «создай заметку Название: текст заметки»';
      }
      final parts = rest.split(':');
      final title = parts.first.trim();
      final content = parts.length > 1 ? parts.sublist(1).join(':').trim() : '';
      return await executeTool(AgentToolCall(
        'create_obsidian_note',
        {'title': title, 'content': content, 'tags': []},
      ));
    }
    if (lower.contains('курс') || lower.contains('валют') || lower.contains('доллар') || lower.contains('евро')) {
      return await executeTool(const AgentToolCall('get_currency_rates', {}));
    }
    if (lower.contains('коммит') || lower.contains('github')) {
      final s = ref.read(settingsProvider);
      if (s.githubOwner.isEmpty || s.githubRepo.isEmpty) {
        return 'Укажи GitHub-репозиторий (owner/repo) в настройках, '
            'чтобы я мог проверить коммиты.';
      }
      final since = DateTime.now()
          .subtract(const Duration(days: 3))
          .toIso8601String()
          .split('T')
          .first;
      return await executeTool(AgentToolCall(
        'get_github_commits',
        {'owner': s.githubOwner, 'repo': s.githubRepo, 'since': since},
      ));
    }
    if (lower.contains('статус')) {
      return _systemStatus();
    }
    if (lower.contains('присед') || lower.contains('отжим') || lower.contains('тренировк')) {
      final s = ref.read(habitsProvider);
      final squat = s.byId('workout_squat');
      final pushups = s.byId('workout_pushups');
      return 'Сегодня: приседания ${squat?.doneToday() ?? false ? 'выполнены' : 'НЕ выполнены'}, '
          'отжимания ${pushups?.doneToday() ?? false ? 'выполнены' : 'НЕ выполнены'}.\n'
          'Отметь их в разделе «Протокол» — видимый прогресс важнее идеальности.';
    }
    if (lower.contains('привет') || lower.contains('здравств')) {
      return 'Привет. Я на связи. Система следит за твоим прогрессом. '
          'Спроси «статус системы», чтобы узнать сводку.';
    }
    if (lower.contains('спасибо')) {
      return 'Всегда пожалуйста. Продолжай дисциплину — система это ценит.';
    }
    if (lower.contains('фото')) {
      return await executeTool(const AgentToolCall(
        'request_photo_verification',
        {
          'task_id': 'offline',
          'description': 'Подтверди любое выполненное дело фото',
        },
      ));
    }
    return 'Записал. Я — контроллер: ставлю задачи, проверяю их через '
        'цифровой след (коммиты, шаги, фото). Команды: «курс валют», '
        '«коммиты», «статус системы», «создай заметку …», «фото».';
  }

  // ------------------------------------------------------- tool calling

  /// Выполнение локального инструмента Hermes.
  Future<String> executeTool(AgentToolCall call) async {
    try {
      switch (call.name) {
        case 'create_obsidian_note':
          final title = call.arguments['title'] as String? ?? '';
          final content = call.arguments['content'] as String? ?? '';
          final obs = ref.read(obsidianProvider.notifier);
          final error = await obs.createNote(title, content);
          if (error == null) {
            ref.read(journalProvider.notifier).logAgentAction(
                  source: 'hermes',
                  type: 'note',
                  title: 'Заметка «$title»',
                  detail: content.length > 200
                      ? '${content.substring(0, 200)}…'
                      : content,
                );
          }
          return error == null
              ? 'Заметка «$title» создана в Vault.'
              : 'Ошибка: $error';

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
          if (target == null) {
            return 'Заметка «$title» не найдена в Vault.';
          }
          final note = await obsN.readNote(target.path);
          final body = note?.content ?? '';
          final preview = body.isEmpty
              ? '(пусто)'
              : (body.length > 500 ? '${body.substring(0, 500)}…' : body);
          return 'Содержимое «$title»:\n$preview';

        case 'get_github_commits':
          final owner = call.arguments['owner'] as String? ?? '';
          final repo = call.arguments['repo'] as String? ?? '';
          final since = call.arguments['since'] as String? ?? '';
          final s = ref.read(settingsProvider);
          final data = await ref.read(githubApiProvider).getCommits(
                owner: owner,
                repo: repo,
                since: since,
                token: s.llmKey,
              );
          final msgs = (data['messages'] as List).take(5).toList();
          final tail = msgs.isEmpty ? '' : 'Последние:\n${msgs.join('\n')}';
          return 'Коммитов с $since: ${data['count']}.\n$tail';

        case 'get_health_data':
          final steps = await ref.read(healthServiceProvider).getStepsToday();
          return steps == null
              ? 'Health Connect недоступен или нет разрешений. Отметь тренировку вручную.'
              : 'Шагов сегодня: $steps.';
        case 'get_currency_rates':
          final rates = await ref.read(nbrbApiProvider).fetchRates();
          if (rates.isEmpty) return 'Курсы недоступны (нет сети).';
          final parts = rates
              .map((r) => '1 ${r.code} = ${r.perUnit.toStringAsFixed(2)} BYN')
              .toList();
          return 'Курсы Нацбанка РБ (${fmtDate(rates.first.date)}):\n${parts.join('\n')}';

        case 'request_photo_verification':
          final desc = call.arguments['description'] as String? ?? '';
          _setState(photoTask: 'offline', photoDesc: desc);
          return 'Отправь фото, подтверждающее: $desc';

        case 'update_dopamine_protocol_status':
          final habitId = call.arguments['habit_id'] as String? ?? '';
          final status = call.arguments['status'] as String? ?? '';
          if (!const ['workout_squat', 'workout_pushups'].contains(habitId) ||
              status != 'done') {
            return 'Ошибка: протокол принимает только выполненную тренировку.';
          }
          final habitsN = ref.read(habitsProvider.notifier);
          final targetReps =
              ref.read(habitsProvider).byId(habitId)?.targetReps ?? 20;
          await habitsN.markWorkout(habitId, targetReps);
          return 'Тренировка отмечена.';

        // ------------------------------------------------ агентные инструменты

        case 'web_search':
          final query = call.arguments['query'] as String? ?? '';
          if (query.isEmpty) return 'Ошибка: пустой запрос';
          return await WebTools.search(query);

        case 'get_webpage':
          final url = call.arguments['url'] as String? ?? '';
          if (url.isEmpty) return 'Ошибка: пустой URL';
          return await WebTools.getPage(url);

        case 'write_file':
          final path = call.arguments['path'] as String? ?? '';
          final content = call.arguments['content'] as String? ?? '';
          if (path.isEmpty) return 'Ошибка: не указан путь';
          final result = await FileTools.writeFile(path, content);
          ref.read(journalProvider.notifier).logAgentAction(
                source: 'hermes',
                type: 'file',
                title: 'Файл $path',
                detail: result,
              );
          return result;

        case 'read_file':
          final path = call.arguments['path'] as String? ?? '';
          if (path.isEmpty) return 'Ошибка: не указан путь';
          return await FileTools.readFile(path);

        case 'list_dir':
          final path = call.arguments['path'] as String? ?? '';
          return await FileTools.listDir(path);

        case 'make_pdf':
          final title = call.arguments['title'] as String? ?? 'Документ';
          final text = call.arguments['text'] as String? ?? '';
          final path = call.arguments['path'] as String? ?? '';
          if (text.isEmpty) return 'Ошибка: пустой текст документа';
          final result =
              await FileTools.makePdf(title: title, text: text, outPath: path);
          ref.read(journalProvider.notifier).logAgentAction(
                source: 'hermes',
                type: 'pdf',
                title: 'PDF: $title',
                detail: result,
              );
          return result;

        case 'read_pdf':
          final path = call.arguments['path'] as String? ?? '';
          final pages = call.arguments['pages'] as String? ?? '';
          if (path.isEmpty) return 'Ошибка: не указан путь';
          return await FileTools.readPdf(path, pages: pages);

        case 'make_study_pdf':
          final title = call.arguments['title'] as String? ?? 'Конспект';
          final text = call.arguments['text'] as String? ?? '';
          if (text.isEmpty) return 'Ошибка: пустой текст конспекта';
          final result = await FileTools.makePdf(
            title: title,
            text: text,
            outPath: 'study/конспекты/${_safeFile(title)}.pdf',
          );
          ref.read(journalProvider.notifier).logAgentAction(
                source: 'hermes',
                type: 'study',
                title: 'Конспект: $title',
                detail: result,
              );
          return result;

        case 'journal_add':
          final type = call.arguments['type'] as String? ?? 'system';
          final jtitle = call.arguments['title'] as String? ?? '';
          final jtext = call.arguments['text'] as String? ?? '';
          if (jtitle.isEmpty) return 'Ошибка: пустое название записи';
          ref.read(journalProvider.notifier).add(
                type: type,
                source: 'hermes',
                title: jtitle,
                text: jtext,
              );
          return 'Запись добавлена в журнал: $jtitle';

        case 'search_knowledge':
          final query = call.arguments['query'] as String? ?? '';
          if (query.isEmpty) return 'Ошибка: пустой запрос';
          return await _searchKnowledge(query);

        case 'set_task':
          final title = call.arguments['title'] as String? ?? '';
          final description = call.arguments['description'] as String? ?? '';
          if (title.isEmpty) return 'Ошибка: пустое название задачи';
          final id = ref.read(tasksProvider.notifier).addTask(title, description);
          ref.read(journalProvider.notifier).logAgentAction(
                source: 'hermes',
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

        default:
          return 'Неизвестный инструмент: ${call.name}';
      }
    } catch (e) {
      return 'Ошибка выполнения: $e';
    }
  }

  // ------------------------------------------------ поиск по базе знаний

  /// Безопасное имя файла (без служебных символов).
  static String _safeFile(String s) {
    final clean = s
        .replaceAll(RegExp(r'[^\wа-яА-ЯёЁ0-9\- ]'), '')
        .trim();
    return clean.isEmpty ? 'document' : clean.replaceAll(' ', '_');
  }

  /// Поиск по заметкам Obsidian Vault: по названию и по содержимому.
  Future<String> _searchKnowledge(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return 'Ошибка: пустой запрос';
    final obsN = ref.read(obsidianProvider.notifier);
    await obsN.refresh();
    final notes = ref.read(obsidianProvider).notes;
    if (notes.isEmpty) return 'Vault не найден или не доступен на этом устройстве.';

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

  // ---------------------------------------------------------- сводка

  Future<String> _systemStatus() async {
    final bank = ref.read(bankProvider);
    final habits = ref.read(habitsProvider);
    final general = bank.generalAccount;
    final total = bank.totalByn(rates: NbrbApi.bundledRates);
    final trainingStreak = habits.trainingStreak();

    return 'СВОДКА СИСТЕМЫ\n'
        '• Деньги: общий счёт ${general?.balance.toStringAsFixed(2) ?? '0'} BYN, '
        'весь плановый капитал ≈ ${total.toStringAsFixed(2)} BYN\n'
        '• Виртуальные карты: ${bank.cards.length}\n'
        '• Протокол тренировок: общий стрик $trainingStreak дн\n'
        '• Тренировки: приседания ${habits.byId('workout_squat')?.doneToday() ?? false ? '✓' : '✗'}, '
        'отжимания ${habits.byId('workout_pushups')?.doneToday() ?? false ? '✓' : '✗'}\n'
        'Продолжай в том же духе.';
  }

  /// Сброс истории чата.
  Future<void> reset() async {
    await _box.clear();
    state = ChatState(messages: _readMessages());
  }
}

final chatProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);
