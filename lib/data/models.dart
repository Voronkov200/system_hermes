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
