// Ручные Hive-адаптеры для моделей "System: Hermes".
//
// build_runner НЕ требуется — адаптеры написаны вручную и полностью
// совместимы с API hive_ce (тот же TypeAdapter, что и в оригинальном Hive).

import 'package:hive_ce/hive.dart';

import 'models.dart';

class AccountAdapter extends TypeAdapter<Account> {
  @override
  final int typeId = 0;

  @override
  Account read(BinaryReader reader) => Account(
        id: reader.readString(),
        name: reader.readString(),
        currency: reader.readString(),
        type: reader.readString(),
        balance: reader.readDouble(),
      );

  @override
  void write(BinaryWriter writer, Account obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.name)
      ..writeString(obj.currency)
      ..writeString(obj.type)
      ..writeDouble(obj.balance);
  }
}

class TransactionAdapter extends TypeAdapter<Transaction> {
  @override
  final int typeId = 1;

  @override
  Transaction read(BinaryReader reader) => Transaction(
        id: reader.readString(),
        type: reader.readString(),
        amount: reader.readDouble(),
        currency: reader.readString(),
        date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
        description: reader.readBool() ? reader.readString() : null,
        rate: reader.readBool() ? reader.readDouble() : null,
      );

  @override
  void write(BinaryWriter writer, Transaction obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.type)
      ..writeDouble(obj.amount)
      ..writeString(obj.currency)
      ..writeInt(obj.date.millisecondsSinceEpoch)
      ..writeBool(obj.description != null);
    if (obj.description != null) writer.writeString(obj.description!);
    writer.writeBool(obj.rate != null);
    if (obj.rate != null) writer.writeDouble(obj.rate!);
  }
}

class CurrencyRateAdapter extends TypeAdapter<CurrencyRate> {
  @override
  final int typeId = 2;

  @override
  CurrencyRate read(BinaryReader reader) => CurrencyRate(
        code: reader.readString(),
        scale: reader.readInt(),
        rate: reader.readDouble(),
        date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      );

  @override
  void write(BinaryWriter writer, CurrencyRate obj) {
    writer
      ..writeString(obj.code)
      ..writeInt(obj.scale)
      ..writeDouble(obj.rate)
      ..writeInt(obj.date.millisecondsSinceEpoch);
  }
}

class ComponentAdapter extends TypeAdapter<Component> {
  @override
  final int typeId = 3;

  @override
  Component read(BinaryReader reader) => Component(
        id: reader.readString(),
        name: reader.readString(),
        type: reader.readString(),
        power: reader.readDouble(),
        price: reader.readInt(),
      );

  @override
  void write(BinaryWriter writer, Component obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.name)
      ..writeString(obj.type)
      ..writeDouble(obj.power)
      ..writeInt(obj.price);
  }
}

class MiningFarmAdapter extends TypeAdapter<MiningFarm> {
  @override
  final int typeId = 4;

  @override
  MiningFarm read(BinaryReader reader) => MiningFarm(
        componentIds: reader.readStringList(),
        osInstalled: reader.readString(),
        driversInstalled: reader.readBool(),
        status: reader.readString(),
        lockUntil: reader.readBool()
            ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
            : null,
        points: reader.readDouble(),
        lastTick: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      );

  @override
  void write(BinaryWriter writer, MiningFarm obj) {
    writer
      ..writeStringList(obj.componentIds)
      ..writeString(obj.osInstalled)
      ..writeBool(obj.driversInstalled)
      ..writeString(obj.status)
      ..writeBool(obj.lockUntil != null);
    if (obj.lockUntil != null) writer.writeInt(obj.lockUntil!.millisecondsSinceEpoch);
    writer
      ..writeDouble(obj.points)
      ..writeInt(obj.lastTick.millisecondsSinceEpoch);
  }
}

class HabitTrackerAdapter extends TypeAdapter<HabitTracker> {
  @override
  final int typeId = 5;

  @override
  HabitTracker read(BinaryReader reader) => HabitTracker(
        id: reader.readString(),
        name: reader.readString(),
        type: reader.readString(),
        targetReps: reader.readInt(),
        currentStreak: reader.readInt(),
        maxStreak: reader.readInt(),
        lastBreakKey: reader.readBool() ? reader.readString() : null,
        entries: reader.readStringList(),
        repsData: reader.readStringList(),
      );

  @override
  void write(BinaryWriter writer, HabitTracker obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.name)
      ..writeString(obj.type)
      ..writeInt(obj.targetReps)
      ..writeInt(obj.currentStreak)
      ..writeInt(obj.maxStreak)
      ..writeBool(obj.lastBreakKey != null);
    if (obj.lastBreakKey != null) writer.writeString(obj.lastBreakKey!);
    writer
      ..writeStringList(obj.entries)
      ..writeStringList(obj.repsData);
  }
}

class ObsidianNoteAdapter extends TypeAdapter<ObsidianNote> {
  @override
  final int typeId = 6;

  @override
  ObsidianNote read(BinaryReader reader) => ObsidianNote(
        path: reader.readString(),
        title: reader.readString(),
        content: reader.readString(),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      );

  @override
  void write(BinaryWriter writer, ObsidianNote obj) {
    writer
      ..writeString(obj.path)
      ..writeString(obj.title)
      ..writeString(obj.content)
      ..writeInt(obj.modifiedAt.millisecondsSinceEpoch);
  }
}

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 7;

  @override
  ChatMessage read(BinaryReader reader) => ChatMessage(
        id: reader.readString(),
        role: reader.readString(),
        text: reader.readString(),
        date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
        toolName: reader.readBool() ? reader.readString() : null,
        toolStatus: reader.readBool() ? reader.readString() : null,
        imagePath: reader.readBool() ? reader.readString() : null,
      );

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.role)
      ..writeString(obj.text)
      ..writeInt(obj.date.millisecondsSinceEpoch)
      ..writeBool(obj.toolName != null);
    if (obj.toolName != null) writer.writeString(obj.toolName!);
    writer.writeBool(obj.toolStatus != null);
    if (obj.toolStatus != null) writer.writeString(obj.toolStatus!);
    writer.writeBool(obj.imagePath != null);
    if (obj.imagePath != null) writer.writeString(obj.imagePath!);
  }
}

/// Регистрация всех адаптеров (вызывается до открытия боксов).
void registerHiveAdapters() {
  Hive
    ..registerAdapter(AccountAdapter())
    ..registerAdapter(TransactionAdapter())
    ..registerAdapter(CurrencyRateAdapter())
    ..registerAdapter(ComponentAdapter())
    ..registerAdapter(MiningFarmAdapter())
    ..registerAdapter(HabitTrackerAdapter())
    ..registerAdapter(ObsidianNoteAdapter())
    ..registerAdapter(ChatMessageAdapter());
}
