// Задачи, которые ставит Hermes.
//
// Хранятся в Hive-боксе «tasks» (typeId 10). Hermes может создавать
// задачи, отмечать их выполненными и спрашивать про прогресс.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/constants.dart';
import '../data/models.dart';

@HiveType(typeId: 10)
class HermesTask {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String description;
  @HiveField(3)
  final String status; // open | done
  @HiveField(4)
  final DateTime createdAt;
  @HiveField(5)
  DateTime? doneAt;

  HermesTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
    this.doneAt,
  });

  HermesTask copyWith({String? status, DateTime? doneAt}) => HermesTask(
        id: id,
        title: title,
        description: description,
        status: status ?? this.status,
        createdAt: createdAt,
        doneAt: doneAt ?? this.doneAt,
      );
}

class HermesTaskAdapter extends TypeAdapter<HermesTask> {
  @override
  final int typeId = 10;

  @override
  HermesTask read(BinaryReader reader) => HermesTask(
        id: reader.readString(),
        title: reader.readString(),
        description: reader.readString(),
        status: reader.readString(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
        doneAt: reader.readBool()
            ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
            : null,
      );

  @override
  void write(BinaryWriter writer, HermesTask obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.title)
      ..writeString(obj.description)
      ..writeString(obj.status)
      ..writeInt(obj.createdAt.millisecondsSinceEpoch)
      ..writeBool(obj.doneAt != null);
    if (obj.doneAt != null) writer.writeInt(obj.doneAt!.millisecondsSinceEpoch);
  }
}

class TasksState {
  final List<HermesTask> tasks;

  const TasksState({required this.tasks});
}

class TasksController extends Notifier<TasksState> {
  late final Box<HermesTask> _box;

  @override
  TasksState build() {
    _box = Hive.box<HermesTask>(BoxNames.tasks);
    final tasks = _box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return TasksState(tasks: tasks);
  }

  /// Создание задачи, возвращает её id.
  String addTask(String title, String description) {
    final task = HermesTask(
      id: genId(),
      title: title.trim(),
      description: description.trim(),
      status: 'open',
      createdAt: DateTime.now(),
    );
    _box.put(task.id, task);
    state = TasksState(tasks: _sorted());
    return task.id;
  }

  Future<void> markDone(String id) async {
    final task = _box.get(id);
    if (task == null || task.status == 'done') return;
    await _box.put(id, task.copyWith(status: 'done', doneAt: DateTime.now()));
    state = TasksState(tasks: _sorted());
  }

  Future<void> removeTask(String id) async {
    await _box.delete(id);
    state = TasksState(tasks: _sorted());
  }

  Future<void> reset() async {
    await _box.clear();
    state = const TasksState(tasks: []);
  }

  List<HermesTask> _sorted() {
    final tasks = _box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }

  int openCount() => _box.values.where((t) => t.status == 'open').length;
}

final tasksProvider =
    NotifierProvider<TasksController, TasksState>(TasksController.new);
