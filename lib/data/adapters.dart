// Ручные Hive-адаптеры для моделей "System: Hermes".
//
// build_runner НЕ требуется — адаптеры написаны вручную и полностью
// совместимы с API hive_ce (тот же TypeAdapter, что и в оригинальном Hive).

import 'package:hive_ce/hive.dart';

import '../services/journal_service.dart';
import '../services/plan/docs_service.dart';
import '../services/study/study_service.dart';
import '../services/tasks_service.dart';
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

class LifeStateAdapter extends TypeAdapter<LifeState> {
  @override
  final int typeId = 8;

  @override
  LifeState read(BinaryReader reader) {
    final lastActionAt = <String, DateTime>{};
    final actionCounts = <String, int>{};

    final actionsCount = reader.readInt();
    for (var i = 0; i < actionsCount; i++) {
      final id = reader.readString();
      lastActionAt[id] = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    }
    final countsCount = reader.readInt();
    for (var i = 0; i < countsCount; i++) {
      final id = reader.readString();
      actionCounts[id] = reader.readInt();
    }

    return LifeState(
      energy: reader.readDouble(),
      mood: reader.readDouble(),
      discipline: reader.readDouble(),
      xp: reader.readInt(),
      lastTick: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      startedAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      unlockedAchievements: reader.readStringList(),
      currentQuestIndex: reader.readInt(),
      questCompletedAt: reader.readBool()
          ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
          : null,
      lastActionAt: lastActionAt,
      actionCounts: actionCounts,
    );
  }

  @override
  void write(BinaryWriter writer, LifeState obj) {
    writer.writeInt(obj.lastActionAt.length);
    obj.lastActionAt.forEach((id, at) {
      writer
        ..writeString(id)
        ..writeInt(at.millisecondsSinceEpoch);
    });
    writer.writeInt(obj.actionCounts.length);
    obj.actionCounts.forEach((id, count) {
      writer
        ..writeString(id)
        ..writeInt(count);
    });
    writer
      ..writeDouble(obj.energy)
      ..writeDouble(obj.mood)
      ..writeDouble(obj.discipline)
      ..writeInt(obj.xp)
      ..writeInt(obj.lastTick.millisecondsSinceEpoch)
      ..writeInt(obj.startedAt.millisecondsSinceEpoch)
      ..writeStringList(obj.unlockedAchievements)
      ..writeInt(obj.currentQuestIndex)
      ..writeBool(obj.questCompletedAt != null);
    if (obj.questCompletedAt != null) {
      writer.writeInt(obj.questCompletedAt!.millisecondsSinceEpoch);
    }
  }
}

class CompanionDataAdapter extends TypeAdapter<CompanionData> {
  @override
  final int typeId = 9;

  @override
  CompanionData read(BinaryReader reader) => CompanionData(
        affinity: reader.readDouble(),
        blockedUntil: reader.readBool()
            ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
            : null,
        lastGreetingKey: reader.readBool() ? reader.readString() : null,
        lastSeenBreakKey: reader.readBool() ? reader.readString() : null,
        seenAchievementCount: reader.readInt(),
        totalRelapses: reader.readInt(),
        seenStreakMilestone: reader.readInt(),
        avatarPath: reader.readString(),
        createdAt: reader.readBool()
            ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
            : null,
        messageCount: reader.readInt(),
        // Новые поля дописываются в конец: старые записи (без них) читаются
        // как есть — после messageCount данных не осталось (availableBytes 0).
        keyFacts: reader.availableBytes == 0 ? [] : reader.readStringList(),
        summarizedUpTo: reader.availableBytes == 0 ? 0 : reader.readInt(),
        socialOutings: reader.availableBytes == 0 ? 0 : reader.readInt(),
        lastSocialOutingKey: reader.availableBytes == 0
            ? null
            : (reader.readBool() ? reader.readString() : null),
        freelanceSteps: reader.availableBytes == 0 ? 0 : reader.readInt(),
        processedNotes: reader.availableBytes == 0 ? [] : reader.readStringList(),
        seenSocialCount: reader.availableBytes == 0 ? 0 : reader.readInt(),
        seenFreelanceCount: reader.availableBytes == 0 ? 0 : reader.readInt(),
        seenQuestIndex: reader.availableBytes == 0 ? 0 : reader.readInt(),
        lastWorkoutBonusKey: reader.availableBytes == 0
            ? null
            : (reader.readBool() ? reader.readString() : null),
        weekStreakBonusGiven:
            reader.availableBytes == 0 ? false : reader.readBool(),
      );

  @override
  void write(BinaryWriter writer, CompanionData obj) {
    writer
      ..writeDouble(obj.affinity)
      ..writeBool(obj.blockedUntil != null);
    if (obj.blockedUntil != null) {
      writer.writeInt(obj.blockedUntil!.millisecondsSinceEpoch);
    }
    writer.writeBool(obj.lastGreetingKey != null);
    if (obj.lastGreetingKey != null) writer.writeString(obj.lastGreetingKey!);
    writer.writeBool(obj.lastSeenBreakKey != null);
    if (obj.lastSeenBreakKey != null) {
      writer.writeString(obj.lastSeenBreakKey!);
    }
    writer
      ..writeInt(obj.seenAchievementCount)
      ..writeInt(obj.totalRelapses)
      ..writeInt(obj.seenStreakMilestone)
      ..writeString(obj.avatarPath)
      ..writeBool(obj.createdAt != null);
    if (obj.createdAt != null) {
      writer.writeInt(obj.createdAt!.millisecondsSinceEpoch);
    }
    writer.writeInt(obj.messageCount);
    writer
      ..writeStringList(obj.keyFacts)
      ..writeInt(obj.summarizedUpTo)
      ..writeInt(obj.socialOutings)
      ..writeBool(obj.lastSocialOutingKey != null);
    if (obj.lastSocialOutingKey != null) {
      writer.writeString(obj.lastSocialOutingKey!);
    }
    writer
      ..writeInt(obj.freelanceSteps)
      ..writeStringList(obj.processedNotes)
      ..writeInt(obj.seenSocialCount)
      ..writeInt(obj.seenFreelanceCount)
      ..writeInt(obj.seenQuestIndex)
      ..writeBool(obj.lastWorkoutBonusKey != null);
    if (obj.lastWorkoutBonusKey != null) {
      writer.writeString(obj.lastWorkoutBonusKey!);
    }
    writer.writeBool(obj.weekStreakBonusGiven);
  }
}

/// Регистрация всех адаптеров (вызывается до открытия боксов).
void registerHiveAdapters() {
  Hive
    ..registerAdapter(AccountAdapter())
    ..registerAdapter(TransactionAdapter())
    ..registerAdapter(CurrencyRateAdapter())
    ..registerAdapter(HabitTrackerAdapter())
    ..registerAdapter(ObsidianNoteAdapter())
    ..registerAdapter(ChatMessageAdapter())
    ..registerAdapter(LifeStateAdapter())
    ..registerAdapter(CompanionDataAdapter())
    ..registerAdapter(HermesTaskAdapter())
    ..registerAdapter(JournalEntryAdapter())
    ..registerAdapter(SourceDocAdapter())
    ..registerAdapter(StudySubjectAdapter())
    ..registerAdapter(StudyParagraphAdapter());
}
