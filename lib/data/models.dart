// Модели данных приложения "System: Hermes".
//
// Аннотации @HiveType/@HiveField добавлены для документации структуры
// (как в ТЗ). Генерация через build_runner НЕ требуется: адаптеры
// написаны вручную в файле adapters.dart и работают с теми же typeId.

import 'package:hive_ce/hive.dart';

/// Генератор простого уникального id (на базе времени).
String genId() => '${DateTime.now().microsecondsSinceEpoch}';

/// Ключ даты вида 2026-08-05 (для стриков и отметок).
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// =====================================================================
// БАНК
// =====================================================================

/// Виртуальный счёт или карта.
@HiveType(typeId: 0)
class Account {
  final String id;
  final String name;
  final String currency; // BYN, USD, EUR, RUB
  final String type; // 'account' | 'card'
  double balance;

  Account({
    required this.id,
    required this.name,
    required this.currency,
    this.type = 'account',
    this.balance = 0,
  });

  /// Основной локальный счёт, на который приходит пенсия.
  static const generalId = 'general_byn';

  /// Стабильный id локальной виртуальной карты для выбранной валюты.
  static String cardId(String currency) =>
      'virtual_${currency.trim().toLowerCase()}';

  /// Старые id нужны только для безопасной миграции существующего баланса.
  static const fuelId = 'fuel';
  static const assetsId = 'assets';
}

/// Финансовая операция.
@HiveType(typeId: 1)
class Transaction {
  final String id;
  final String type; // deposit | transfer | withdrawal | conversion | fine | bonus
  final double amount;
  final String currency;
  final DateTime date;
  final String? description;
  final double? rate; // курс при конвертации

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.date,
    this.description,
    this.rate,
  });
}

/// Курс валюты от Нацбанка РБ.
@HiveType(typeId: 2)
class CurrencyRate {
  final String code; // USD, EUR
  final int scale; // шкала (обычно 1)
  final double rate; // столько BYN за scale единиц
  final DateTime date;

  CurrencyRate({
    required this.code,
    required this.scale,
    required this.rate,
    required this.date,
  });

  /// Сколько BYN стоит 1 единица валюты.
  double get perUnit => rate / scale;
}

// =====================================================================
// ПРОТОКОЛ ДОФАМИНОВОЙ СТАБИЛЬНОСТИ
// =====================================================================

/// Привычка (вредная 'bad' или полезная 'good').
@HiveType(typeId: 5)
class HabitTracker {
  final String id;
  final String name;
  final String type; // 'bad' | 'good'
  final int targetReps; // для тренировок (например 20)
  int currentStreak;
  int maxStreak;
  String? lastBreakKey; // дата последнего срыва (для 'bad')
  final List<String> entries; // ключи дат отметок
  final List<String> repsData; // 'дата:количество повторений' (для тренировок)

  HabitTracker({
    required this.id,
    required this.name,
    required this.type,
    this.targetReps = 20,
    this.currentStreak = 0,
    this.maxStreak = 0,
    this.lastBreakKey,
    List<String>? entries,
    List<String>? repsData,
  })  : entries = entries ?? [],
        repsData = repsData ?? [];

  bool isDoneOn(String key) => entries.contains(key);

  bool doneToday() => isDoneOn(dateKey(DateTime.now()));

  int repsOn(String key) {
    for (final r in repsData) {
      final parts = r.split(':');
      if (parts.length == 2 && parts[0] == key) return int.tryParse(parts[1]) ?? 0;
    }
    return 0;
  }
}

// =====================================================================
// OBSIDIAN
// =====================================================================

/// Заметка Obsidian (путь + заголовок + содержимое).
@HiveType(typeId: 6)
class ObsidianNote {
  final String path;
  final String title;
  final String content;
  final DateTime modifiedAt;

  ObsidianNote({
    required this.path,
    required this.title,
    required this.content,
    required this.modifiedAt,
  });
}

// =====================================================================
// ЖИЗНЬ (RPG-механики "Богатой жизни", адаптированные под реальность)
// =====================================================================

/// Показатели и прогресс "Жизни": энергия, настроение, дисциплина, XP.
@HiveType(typeId: 8)
class LifeState {
  double energy; // 0-100
  double mood; // 0-100
  double discipline; // 0-100
  int xp;
  DateTime lastTick; // момент последнего автотика
  DateTime startedAt; // дата старта "Жизни"
  final List<String> unlockedAchievements; // id открытых достижений
  int currentQuestIndex; // индекс текущего квеста
  DateTime? questCompletedAt; // когда открыт квест (для старения)
  final Map<String, DateTime> lastActionAt; // id действия -> последний раз
  final Map<String, int> actionCounts; // id действия -> сколько раз

  LifeState({
    this.energy = 100,
    this.mood = 100,
    this.discipline = 100,
    this.xp = 0,
    required this.lastTick,
    required this.startedAt,
    List<String>? unlockedAchievements,
    this.currentQuestIndex = 0,
    this.questCompletedAt,
    Map<String, DateTime>? lastActionAt,
    Map<String, int>? actionCounts,
  })  : unlockedAchievements = unlockedAchievements ?? [],
        lastActionAt = lastActionAt ?? {},
        actionCounts = actionCounts ?? {};

  factory LifeState.empty() =>
      LifeState(lastTick: DateTime.now(), startedAt: DateTime.now());

  /// Дней с начала "Жизни".
  int get daysInSystem =>
      DateTime.now().difference(startedAt).inDays + 1;
}

// =====================================================================
// КОМПАНЬОН "АНАСТАСИЯ"
// =====================================================================

/// Состояние ИИ-компаньона "Анастасия": симпатия, память, вехи реальных
/// действий. Affinity растёт ТОЛЬКО от позитивных событий; штрафов,
/// блокировок и «холодных» уровней нет (спецификация «Идея ИИ-компаньон»).
@HiveType(typeId: 9)
class CompanionData {
  /// 0-100, накопленная симпатия (не формула — сумма реальных событий).
  double affinity;

  /// Оставлено для совместимости со старыми данными; больше не используется.
  DateTime? blockedUntil;
  String? lastGreetingKey; // dateKey последнего приветствия (раз в день)
  String? lastSeenBreakKey; // последний обработанный срыв протокола
  int seenAchievementCount; // сколько достижений Жизни обработано
  int totalRelapses; // всего срывов за всё время (счётчик, не штраф)
  int seenStreakMilestone; // последний пройденный рубеж стрика
  String avatarPath; // фото из галереи (аватар/фон чата)
  DateTime? createdAt;
  int messageCount; // всего сообщений от Анастасии

  // ---- Память (двухуровневая: keyFacts + свежий хвост + суммаризация) ----

  /// Вечные факты: никогда не сжимаются и не удаляются.
  List<String> keyFacts;

  /// Сколько сообщений из начала истории уже ушло в keyFacts.
  int summarizedUpTo;

  // ---- Вехи реальных действий (только положительные события) ----

  /// Самостоятельные выходы из дома (walk/store/atm) — приоритет №1.
  int socialOutings;

  /// dateKey последнего самостоятельного выхода из дома.
  String? lastSocialOutingKey;

  /// Шаги фриланса (действие 'freelance' / коммиты).
  int freelanceSteps;

  /// Заголовки заметок Obsidian, уже учтённых в affinity.
  List<String> processedNotes;

  /// Сумма счётчиков действий walk+store+atm на момент последней проверки.
  int seenSocialCount;

  /// Счётчик действия 'freelance' на момент последней проверки.
  int seenFreelanceCount;

  /// Индекс квеста Жизни на момент последней проверки.
  int seenQuestIndex;

  /// dateKey последнего дня с бонусом за тренировку (+3).
  String? lastWorkoutBonusKey;

  /// Разовый бонус +25 за стрик 7 дней (выдаётся один раз).
  bool weekStreakBonusGiven;

  CompanionData({
    this.affinity = 5,
    this.blockedUntil,
    this.lastGreetingKey,
    this.lastSeenBreakKey,
    this.seenAchievementCount = 0,
    this.totalRelapses = 0,
    this.seenStreakMilestone = 0,
    this.avatarPath = '',
    this.createdAt,
    this.messageCount = 0,
    List<String>? keyFacts,
    this.summarizedUpTo = 0,
    this.socialOutings = 0,
    this.lastSocialOutingKey,
    this.freelanceSteps = 0,
    List<String>? processedNotes,
    this.seenSocialCount = 0,
    this.seenFreelanceCount = 0,
    this.seenQuestIndex = 0,
    this.lastWorkoutBonusKey,
    this.weekStreakBonusGiven = false,
  })  : keyFacts = keyFacts ?? [],
        processedNotes = processedNotes ?? [];

  factory CompanionData.empty() => CompanionData(createdAt: DateTime.now());
}

// =====================================================================
// ЧАТ С HERMES
// =====================================================================

/// Сообщение в чате.
@HiveType(typeId: 7)
class ChatMessage {
  final String id;
  final String role; // user | hermes | system
  final String text;
  final DateTime date;
  final String? toolName; // имя вызванного инструмента
  final String? toolStatus; // ok | error | pending
  final String? imagePath; // фото-верификация

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.date,
    this.toolName,
    this.toolStatus,
    this.imagePath,
  });
}

/// Команда Tool Calling от Hermes.
class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  ToolCall({required this.name, required this.arguments});

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        name: json['name'] as String? ?? '',
        arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ?? {},
      );

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};
}
