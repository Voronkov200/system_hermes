// Журнал изменений: табличка со всеми действиями и голосовыми записями.
//
// Каждая запись: когда, кто (Hermes/пользователь), что сделано
// (создан файл, PDF, задача, транскрипт голосовой записи, конспект).
// Живёт в Hive-боксе «journal» (typeId 11).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';

@HiveType(typeId: 11)
class JournalEntry {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final DateTime date;
  @HiveField(2)
  final String type; // voice | file | pdf | task | note | study | system
  @HiveField(3)
  final String source; // user | hermes | system
  @HiveField(4)
  final String title;
  @HiveField(5)
  final String text;

  JournalEntry({
    required this.id,
    required this.date,
    required this.type,
    required this.source,
    required this.title,
    required this.text,
  });
}

class JournalEntryAdapter extends TypeAdapter<JournalEntry> {
  @override
  final int typeId = 11;

  @override
  JournalEntry read(BinaryReader reader) => JournalEntry(
        id: reader.readString(),
        date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
        type: reader.readString(),
        source: reader.readString(),
        title: reader.readString(),
        text: reader.readString(),
      );

  @override
  void write(BinaryWriter writer, JournalEntry obj) {
    writer
      ..writeString(obj.id)
      ..writeInt(obj.date.millisecondsSinceEpoch)
      ..writeString(obj.type)
      ..writeString(obj.source)
      ..writeString(obj.title)
      ..writeString(obj.text);
  }
}

class JournalState {
  final List<JournalEntry> entries;

  const JournalState({required this.entries});
}

class JournalController extends Notifier<JournalState> {
  late final Box<JournalEntry> _box;

  @override
  JournalState build() {
    _box = Hive.box<JournalEntry>(BoxNames.journal);
    return JournalState(entries: _sorted());
  }

  /// Добавление записи в журнал (лимит 1500 записей — старые удаляются).
  void add({
    required String type,
    required String source,
    required String title,
    required String text,
  }) {
    final entry = JournalEntry(
      id: genId(),
      date: DateTime.now(),
      type: type,
      source: source,
      title: title.trim().isEmpty ? '(без названия)' : title.trim(),
      text: text.trim(),
    );
    _box.put(entry.id, entry);
    if (_box.length > 1500) {
      // Удаляем самую старую запись из всего бокса, а не из списка из 500.
      var oldest = _box.values.first;
      for (final v in _box.values) {
        if (v.date.isBefore(oldest.date)) oldest = v;
      }
      _box.delete(oldest.id);
    }
    state = JournalState(entries: _sorted());
  }

  /// Короткая запись о действии агента (файл/PDF/задача).
  void logAgentAction({
    required String source,
    required String type,
    required String title,
    String? detail,
  }) {
    add(
      type: type,
      source: source,
      title: title,
      text: detail ?? '',
    );
  }

  /// Удаление записи. Синхронное: элемент уходит из списка в том же кадре,
  /// чтобы Dismissible не падал с «still part of the tree».
  void remove(String id) {
    _box.delete(id);
    state = JournalState(entries: _sorted());
  }

  Future<void> clear() async {
    await _box.clear();
    state = const JournalState(entries: []);
  }

  List<JournalEntry> _sorted() {
    final list = _box.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list.take(500).toList();
  }
}

final journalProvider =
    NotifierProvider<JournalController, JournalState>(JournalController.new);
