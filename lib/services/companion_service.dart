// Модуль "Настя": ИИ-компаньон с системой симпатии (Affinity).
//
// Настя — наблюдатель: она читает состояние Протокола, Жизни и Банка и
// реагирует на события (срыв, достижение, стрик-рубеж, новый день).
// Циклических зависимостей нет: другие сервисы её не импортируют.
//
// Ответы: Groq/OpenAI-совместимый LLM (если задан ключ в настройках)
// или офлайн-шаблоны.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../data/companion_catalog.dart';
import '../data/models.dart';
import 'bank_service.dart';
import 'habits_service.dart';
import 'life_service.dart';
import 'settings_service.dart';

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
      state = _readState(thinking: false);
      _nastyaSays('Я сказала — не пиши. Осталось ~$hours ч. '
          'Переживёшь. Займись делом.');
      return;
    }

    String reply;
    try {
      final s = ref.read(settingsProvider);
      if (s.companionApiKey.trim().isNotEmpty) {
        reply = await _remoteRequest(trimmed, s);
      } else {
        reply = offlineReplyFor(trimmed, _levelIndex());
      }
    } catch (e) {
      reply = 'Что-то пошло не так, и я не получила ответ от своего мозга. '
          'Попробуй позже — или настрой мой API ключ. Я умею ждать.';
    }

    state = _readState(thinking: false);
    _nastyaSays(reply);
  }

  int _levelIndex() {
    final lvl = levelForAffinity(_computeAffinity());
    return relationLevels.indexOf(lvl).clamp(0, relationLevels.length - 1);
  }

  /// Запрос к Groq/OpenAI-совместимому API.
  Future<String> _remoteRequest(String text, SettingsState s) async {
    final ctx = _context();
    final all = _readMessages();
    final tail = all.length > 16 ? all.sublist(all.length - 16) : all;
    final history = tail.map((m) => {
          'role': m.role == 'user' ? 'user' : 'assistant',
          'content': m.text,
        }).toList();

    final res = await http
        .post(
          Uri.parse(s.companionApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${s.companionApiKey}',
          },
          body: jsonEncode({
            'model': s.companionModel,
            'messages': [
              {'role': 'system', 'content': ctx.toSystemPrompt()},
              ...history,
            ],
            'temperature': 0.85,
            'max_tokens': 350,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List? ?? const [];
    if (choices.isEmpty) throw Exception('Пустой ответ API');
    final content = (choices.first as Map)['message']?['content'] as String?;
    final trimmed = (content ?? '').trim();
    return trimmed.isEmpty ? '…' : trimmed;
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
