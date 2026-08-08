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
  final String currency; // BYN, USD, EUR
  final String type; // 'account' | 'card'
  double balance;

  Account({
    required this.id,
    required this.name,
    required this.currency,
    this.type = 'account',
    this.balance = 0,
  });

  /// Зарезервированные id счетов.
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
// МАЙНИНГ И PC BUILDER
// =====================================================================

/// Комплектующая для ПК/фермы.
@HiveType(typeId: 3)
class Component {
  final String id;
  final String name;
  final String type; // CPU | GPU | RAM | Storage
  final double power; // виртуальная мощность
  final int price; // цена в очках

  const Component({
    required this.id,
    required this.name,
    required this.type,
    required this.power,
    this.price = 0,
  });
}

/// Каталог доступных комплектующих.
class ComponentCatalog {
  static const List<Component> all = [
    Component(id: 'cpu_celeron', name: 'Intel Celeron G5905', type: 'CPU', power: 40, price: 50),
    Component(id: 'cpu_i5', name: 'Intel Core i5-10400F', type: 'CPU', power: 120, price: 200),
    Component(id: 'cpu_ryzen', name: 'AMD Ryzen 5 5600X', type: 'CPU', power: 160, price: 300),
    Component(id: 'gpu_gt710', name: 'NVIDIA GT 710', type: 'GPU', power: 30, price: 40),
    Component(id: 'gpu_gtx1060', name: 'NVIDIA GTX 1060', type: 'GPU', power: 220, price: 350),
    Component(id: 'gpu_rtx3060', name: 'NVIDIA RTX 3060', type: 'GPU', power: 380, price: 600),
    Component(id: 'ram_4gb', name: 'RAM 4 ГБ DDR4', type: 'RAM', power: 20, price: 30),
    Component(id: 'ram_8gb', name: 'RAM 8 ГБ DDR4', type: 'RAM', power: 45, price: 80),
    Component(id: 'ram_16gb', name: 'RAM 16 ГБ DDR4', type: 'RAM', power: 80, price: 150),
    Component(id: 'ssd_128', name: 'SSD 128 ГБ', type: 'Storage', power: 25, price: 40),
    Component(id: 'ssd_512', name: 'SSD 512 ГБ NVMe', type: 'Storage', power: 70, price: 120),
    Component(id: 'ssd_1tb', name: 'SSD 1 ТБ NVMe', type: 'Storage', power: 120, price: 220),
  ];

  static Component? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Состояние майнинг-фермы.
@HiveType(typeId: 4)
class MiningFarm {
  final List<String> componentIds; // выбранные комплектующие
  final String osInstalled; // 'none' | 'linux' | 'windows'
  final bool driversInstalled;
  final String status; // offline | building | online | locked
  DateTime? lockUntil; // блокировка после срыва протокола
  double points; // накопленные очки
  DateTime lastTick; // последнее начисление

  MiningFarm({
    required this.componentIds,
    this.osInstalled = 'none',
    this.driversInstalled = false,
    this.status = 'offline',
    this.lockUntil,
    this.points = 0,
    required this.lastTick,
  });

  factory MiningFarm.empty() =>
      MiningFarm(componentIds: [], lastTick: DateTime.now());

  double get basePower {
    double sum = 0;
    for (final id in componentIds) {
      final c = ComponentCatalog.byId(id);
      if (c != null) sum += c.power;
    }
    return sum;
  }
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
// КОМПАНЬОН "НАСТЯ"
// =====================================================================

/// Состояние ИИ-компаньона "Настя": симпатия, блокировки, фото.
@HiveType(typeId: 9)
class CompanionData {
  double affinity; // 0-100, кэш формулы от прогресса
  DateTime? blockedUntil; // чат недоступен до этого момента (после срыва)
  String? lastGreetingKey; // dateKey последнего приветствия (раз в день)
  String? lastSeenBreakKey; // последний обработанный срыв протокола
  int seenAchievementCount; // сколько достижений Жизни обработано
  int totalRelapses; // всего срывов за всё время
  int seenStreakMilestone; // последний пройденный рубеж стрика
  String avatarPath; // фото из галереи (аватар/фон чата)
  DateTime? createdAt;
  int messageCount; // всего сообщений от Насти

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
  });

  factory CompanionData.empty() => CompanionData(createdAt: DateTime.now());

  bool get blocked => blockedUntil != null && blockedUntil!.isAfter(DateTime.now());
}

// =====================================================================
// МОЙ ПК (виртуальный компьютер с установкой Windows)
// =====================================================================

/// Состояние виртуального ПК: фазы включения, установки и рабочего стола.
@HiveType(typeId: 12)
class MyPcState {
  /// Фаза: off | bios | setup | reboot | desktop
  String phase;
  int setupStage; // 0..3 — этап установки
  double setupProgress; // 0..100
  DateTime? phaseStartedAt; // начало текущей фазы (для тайминга)
  DateTime? installedAt; // момент завершения установки
  String osName; // имя сборки
  String edition; // редакция Windows
  double imageSizeGb; // реальный размер образа install.esd
  int sourceEditions; // сколько редакций было в оригинальном ISO
  final List<String> tweaks; // применённые к сборке твики
  int bootCount; // сколько раз включался

  // Персонализация.
  String wallpaperId; // id обоев рабочего стола
  String computerName; // имя компьютера
  String taskbarTheme; // dark | light | blue

  /// Приоритет загрузки в BIOS: dvd | hdd | usb.
  String bootPriority;

  MyPcState({
    this.phase = 'off',
    this.setupStage = 0,
    this.setupProgress = 0,
    this.phaseStartedAt,
    this.installedAt,
    this.osName = 'Windows 11 Pro — Hermes Edition',
    this.edition = 'Windows 11 Pro',
    this.imageSizeGb = 4.4,
    this.sourceEditions = 6,
    List<String>? tweaks,
    this.bootCount = 0,
    this.wallpaperId = 'bloom',
    this.computerName = 'HERMES-01',
    this.taskbarTheme = 'light',
    this.bootPriority = 'dvd',
  }) : tweaks = tweaks ?? [];

  factory MyPcState.empty() => MyPcState();

  bool get installed => phase == 'desktop';
}

/// Виртуальный файл/папка в файловой системе виртуального ПК.
@HiveType(typeId: 13)
class VirtualFsFile {
  final String path; // полный путь, например C:\Users\Hermes\Desktop\Привет.txt
  final String content; // содержимое (для папок пусто)
  final bool isFolder;

  /// Оригинальный путь до перемещения в Корзину (null — обычный файл).
  final String? originalPath;

  const VirtualFsFile({
    required this.path,
    this.content = '',
    this.isFolder = false,
    this.originalPath,
  });

  /// Файл находится в Корзине.
  bool get recycled => originalPath != null;

  String get name {
    final parts = path.split('\\');
    return parts.isEmpty ? path : parts.last;
  }

  /// Родительский каталог ('C:\Users\Hermes' для 'C:\Users\Hermes\Desktop').
  String get parent {
    final parts = path.split('\\');
    if (parts.length <= 2) return '';
    return parts.sublist(0, parts.length - 1).join('\\');
  }

  /// Имя без расширения (для папок — само имя).
  String get stem {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

/// Каталог виртуальных файлов "Моего ПК".
class VirtualFsCatalog {
  VirtualFsCatalog._();

  /// Виртуальный образ сборки (символизирует реальный install.esd).
  static const esdFileName = 'Win11_25H2_Hermes_ru-RU.esd';

  /// Каталог Корзины.
  static const recycleBinPath = r'C:\$Recycle.Bin';

  static List<VirtualFsFile> defaults() => const [
        VirtualFsFile(path: r'C:\Windows', isFolder: true),
        VirtualFsFile(path: r'C:\Program Files', isFolder: true),
        VirtualFsFile(path: r'C:\Users', isFolder: true),
        VirtualFsFile(path: r'C:\Hermes OS', isFolder: true),
        VirtualFsFile(path: r'C:\Drivers', isFolder: true),
        VirtualFsFile(path: r'C:\$Recycle.Bin', isFolder: true),
        VirtualFsFile(path: r'C:\Windows\system32', isFolder: true),
        VirtualFsFile(path: r'C:\Windows\explorer.exe', content: 'Оболочка Windows 11.'),
        VirtualFsFile(path: r'C:\Windows\win.ini', content: '; для совместимости со старыми программами\r\n[fonts]\r\n[extensions]'),
        VirtualFsFile(path: r'C:\Program Files\Groq CLI', isFolder: true),
        VirtualFsFile(path: r'C:\Program Files\Groq CLI\groq.exe', content: 'Интерфейс командной строки Groq.'),
        VirtualFsFile(path: r'C:\Drivers\GPU_Driver.exe', content: 'Установщик драйвера видеокарты для майнинг-фермы.'),
        VirtualFsFile(path: r'C:\Users\Hermes', isFolder: true),
        VirtualFsFile(path: r'C:\Users\Hermes\Desktop', isFolder: true),
        VirtualFsFile(path: r'C:\Users\Hermes\Documents', isFolder: true),
        VirtualFsFile(path: r'C:\Users\Hermes\Downloads', isFolder: true),
        VirtualFsFile(path: r'C:\Users\Hermes\Desktop\Привет.txt', content: 'Добро пожаловать в Hermes OS!\r\nТвой виртуальный ПК работает.'),
        VirtualFsFile(path: r'C:\Users\Hermes\Desktop\Сборка Hermes OS.txt', content: 'Урезанная сборка Windows 11 Pro (25H2, RU)\r\nРедакций в оригинале: 6 -> 1\r\nОбраз сжат в ESD.\r\nУдалены рекламные приложения.'),
        VirtualFsFile(path: r'C:\Users\Hermes\Documents\План.txt', content: 'Протокол Дофаминовой Стабильности:\r\n- приседания и отжимания каждый день\r\n- без срывов 30 дней'),
        VirtualFsFile(path: r'C:\Users\Hermes\Documents\Дневник.txt', content: 'День 1: система запущена.'),
        VirtualFsFile(path: r'C:\Users\Hermes\Downloads\Win11_25H2_Hermes_ru-RU.esd', content: 'install.esd — сжатая сборка Windows 11 Pro Hermes Edition.'),
        VirtualFsFile(path: r'C:\Hermes OS\README.txt', content: 'Hermes OS — твоя сборка Windows 11.\r\nКастомизация: твики, удаление мусора, ESD-сжатие.'),
        VirtualFsFile(path: r'C:\Hermes OS\unattend.xml', content: '<unattend>Автовход: Hermes. OOBE: пропущен.</unattend>'),
        VirtualFsFile(path: r'C:\Hermes OS\tweaks.txt', content: 'Телеметрия: off\r\nПоиск Bing: off\r\nРеклама в Пуске: off'),
      ];
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
