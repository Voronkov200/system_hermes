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
import 'life_service.dart';
import 'mining_service.dart';
import 'nbrb_api.dart';
import 'obsidian_service.dart';
import 'settings_service.dart';

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
      _box.put(genId(), ChatMessage(
        id: '',
        role: 'hermes',
        text: 'Система HERMES онлайн. Я контроллер твоей цифровой ОС жизни.\n'
            'Доступные команды: «создай заметку …», «курс валют», «коммиты», '
            '«статус системы», «отметить тренировку», «фото-верификация».',
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

  void _setState({bool? thinking, String? photoTask, String? photoDesc}) {
    state = ChatState(
      messages: _readMessages(),
      thinking: thinking ?? state.thinking,
      pendingPhotoTask: photoTask ?? state.pendingPhotoTask,
      pendingPhotoDescription: photoDesc ?? state.pendingPhotoDescription,
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
      if (s.hermesUrl.trim().isNotEmpty) {
        reply = await _remoteRequest(trimmed, s);
      } else if (s.llmKey.isNotEmpty) {
        reply = await _llmRequest(trimmed, s);
      } else {
        reply = await _offlineRequest(trimmed);
      }
    } catch (e) {
      debugPrint('[Hermes] LLM error: $e');
      reply = 'Ошибка соединения: $e\n\n'
          'Проверь API-ключ/URL в настройках (или работай в офлайн-режиме).';
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
      _setState(photoTask: null, photoDesc: null);
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
        final call = ToolCall.fromJson(raw.cast<String, dynamic>());
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

  /// Ответ через OpenAI-совместимый LLM (OpenCode Zen и т.п.).
  Future<String> _llmRequest(String text, SettingsState s) async {
    final bank = ref.read(bankProvider);
    final mining = ref.read(miningProvider);
    final habits = ref.read(habitsProvider);
    final life = ref.read(lifeProvider).state;
    final fuel = bank.byId(Account.fuelId)?.balance ?? 0;
    final assets = bank.byId(Account.assetsId)?.balance ?? 0;

    final system = buildHermesSystemPrompt(
      fuelBalance: fuel,
      assetsBalance: assets,
      cleanStreak: habits.cleanStreak(),
      lifeLevel: 1 + (life.xp / 100).floor(),
      xp: life.xp,
      farmOnline: mining.farm.status == 'online',
      farmLocked: mining.locked,
      farmHashRate: mining.hashRate,
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

    final res = await http
        .post(
          Uri.parse(s.companionApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${s.llmKey}',
          },
          body: jsonEncode({
            'model': s.companionModel,
            'messages': [
              {'role': 'system', 'content': system},
              ...history,
            ],
            'temperature': 0.7,
            'max_tokens': 450,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode != 200) {
      final reason = switch (res.statusCode) {
        401 => 'неверный API-ключ (401)',
        404 => 'неверный URL или модель (404)',
        429 => 'превышен лимит запросов (429)',
        _ => 'ошибка сервера ИИ',
      };
      throw Exception('HTTP ${res.statusCode} — $reason');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List? ?? const [];
    if (choices.isEmpty) throw Exception('Пустой ответ API');
    final content = (choices.first as Map)['message']?['content'] as String?;
    final trimmed = (content ?? '').trim();
    return trimmed.isEmpty ? '…' : trimmed;
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
      return await executeTool(ToolCall(
        name: 'create_obsidian_note',
        arguments: {'title': title, 'content': content, 'tags': []},
      ));
    }
    if (lower.contains('курс') || lower.contains('валют') || lower.contains('доллар') || lower.contains('евро')) {
      return await executeTool(ToolCall(name: 'get_currency_rates', arguments: {}));
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
      return await executeTool(ToolCall(
        name: 'get_github_commits',
        arguments: {'owner': s.githubOwner, 'repo': s.githubRepo, 'since': since},
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
          'Отметь их в разделе «Протокол» — это даст +10% хешрейта за каждую.';
    }
    if (lower.contains('сорва') || lower.contains('срыв')) {
      return 'Срыв протокола = штраф ${AppConstants.habitFine} BYN и блокировка '
          'фермы на 24 ч. Отметь срыв честно в разделе «Протокол». '
          'Держись. Возвращайся в строй.';
    }
    if (lower.contains('привет') || lower.contains('здравств')) {
      return 'Привет. Я на связи. Система следит за твоим прогрессом. '
          'Спроси «статус системы», чтобы узнать сводку.';
    }
    if (lower.contains('спасибо')) {
      return 'Всегда пожалуйста. Продолжай дисциплину — система это ценит.';
    }
    if (lower.contains('фото')) {
      return await executeTool(ToolCall(
        name: 'request_photo_verification',
        arguments: {'task_id': 'offline', 'description': 'Подтверди любое выполненное дело фото'},
      ));
    }
    return 'Записал. Я — контроллер: ставлю задачи, проверяю их через '
        'цифровой след (коммиты, шаги, фото). Команды: «курс валют», '
        '«коммиты», «статус системы», «создай заметку …», «фото».';
  }

  // ------------------------------------------------------- tool calling

  /// Выполнение локального инструмента Hermes.
  Future<String> executeTool(ToolCall call) async {
    try {
      switch (call.name) {
        case 'create_obsidian_note':
          final title = call.arguments['title'] as String? ?? '';
          final content = call.arguments['content'] as String? ?? '';
          final obs = ref.read(obsidianProvider.notifier);
          final error = await obs.createNote(title, content);
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
          final habitsN = ref.read(habitsProvider.notifier);
          final targetReps =
              ref.read(habitsProvider).byId(habitId)?.targetReps ?? 20;
          if (status == 'broken') {
            await habitsN.markBreak(habitId);
            return 'Срыв отмечен. Штраф и блокировка фермы применены.';
          }
          await habitsN.markWorkout(habitId, targetReps);
          return 'Тренировка отмечена.';

        default:
          return 'Неизвестный инструмент: ${call.name}';
      }
    } catch (e) {
      return 'Ошибка выполнения: $e';
    }
  }

  // ---------------------------------------------------------- сводка

  Future<String> _systemStatus() async {
    final bank = ref.read(bankProvider);
    final mining = ref.read(miningProvider);
    final habits = ref.read(habitsProvider);
    final s = ref.read(settingsProvider);

    final fuel = bank.byId(Account.fuelId);
    final assets = bank.byId(Account.assetsId);
    final clean = habits.cleanStreak();
    final farmStatus = mining.farm.status == 'online'
        ? 'ОНЛАЙН'
        : mining.locked
            ? 'ЗАБЛОКИРОВАНА'
            : 'НЕ ЗАПУЩЕНА';

    return 'СВОДКА СИСТЕМЫ\n'
        '• Банк: Топливо ${fuel?.balance.toStringAsFixed(2) ?? '0'} BYN, '
        'Активы ${assets?.balance.toStringAsFixed(2) ?? '0'} ${s.assetsCurrency}\n'
        '• Ферма: $farmStatus, хешрейт ${mining.hashRate.toStringAsFixed(0)}, '
        'очки ${mining.farm.points.toStringAsFixed(0)}\n'
        '• Протокол: $clean дней без срывов (макс ${habits.byId('abstinence')?.maxStreak ?? 0})\n'
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
