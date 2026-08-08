// Тесты Hive-адаптеров: round-trip новых данных и совместимость
// со старыми форматами (сценарий обновления приложения без краша).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:system_hermes/data/adapters.dart';
import 'package:system_hermes/data/models.dart';

/// Адаптер, который пишет СТАРЫЙ формат MyPcState (до персонализации).
/// Используется для имитации данных, оставшихся от прежней версии.
class LegacyMyPcStateAdapter extends MyPcStateAdapter {
  @override
  void write(BinaryWriter writer, MyPcState obj) {
    // Как в старом адаптере: длина списка через writeInt + цикл writeString.
    writer.writeInt(obj.tweaks.length);
    for (final t in obj.tweaks) {
      writer.writeString(t);
    }
    writer
      ..writeString(obj.phase)
      ..writeInt(obj.setupStage)
      ..writeDouble(obj.setupProgress)
      ..writeBool(obj.phaseStartedAt != null);
    if (obj.phaseStartedAt != null) {
      writer.writeInt(obj.phaseStartedAt!.millisecondsSinceEpoch);
    }
    writer.writeBool(obj.installedAt != null);
    if (obj.installedAt != null) {
      writer.writeInt(obj.installedAt!.millisecondsSinceEpoch);
    }
    writer
      ..writeString(obj.osName)
      ..writeString(obj.edition)
      ..writeDouble(obj.imageSizeGb)
      ..writeInt(obj.sourceEditions)
      ..writeInt(obj.bootCount);
  }
}

/// Промежуточный формат: персонализация есть, bootPriority ещё нет.
class MidMyPcStateAdapter extends MyPcStateAdapter {
  @override
  void write(BinaryWriter writer, MyPcState obj) {
    // Пишем всё как в версии с персонализацией, но без bootPriority.
    writer.writeInt(obj.tweaks.length);
    for (final t in obj.tweaks) {
      writer.writeString(t);
    }
    writer
      ..writeString(obj.phase)
      ..writeInt(obj.setupStage)
      ..writeDouble(obj.setupProgress)
      ..writeBool(obj.phaseStartedAt != null);
    if (obj.phaseStartedAt != null) {
      writer.writeInt(obj.phaseStartedAt!.millisecondsSinceEpoch);
    }
    writer.writeBool(obj.installedAt != null);
    if (obj.installedAt != null) {
      writer.writeInt(obj.installedAt!.millisecondsSinceEpoch);
    }
    writer
      ..writeString(obj.osName)
      ..writeString(obj.edition)
      ..writeDouble(obj.imageSizeGb)
      ..writeInt(obj.sourceEditions)
      ..writeInt(obj.bootCount)
      ..writeBool(true)
      ..writeString(obj.wallpaperId)
      ..writeString(obj.computerName)
      ..writeString(obj.taskbarTheme);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hermes_hive_test');
    Hive.init(tempDir.path);
    Hive.resetAdapters();
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('MyPcState: round-trip с персонализацией', () async {
    Hive.registerAdapter(MyPcStateAdapter());
    final box = await Hive.openBox<MyPcState>('myPc');
    final state = MyPcState(
      phase: 'desktop',
      setupStage: 3,
      setupProgress: 100,
      phaseStartedAt: DateTime(2026, 8, 7, 12, 0),
      installedAt: DateTime(2026, 8, 7, 12, 1),
      osName: 'Windows 11 Pro — Hermes Edition',
      edition: 'Windows 11 Pro',
      imageSizeGb: 4.4,
      sourceEditions: 6,
      tweaks: ['remove_ads', 'cleanup'],
      bootCount: 7,
      wallpaperId: 'ocean',
      computerName: 'MY-PC',
      taskbarTheme: 'blue',
      bootPriority: 'hdd',
      bottomBarHidden: true,
    );
    await box.put('state', state);
    final loaded = box.get('state')!;
    expect(loaded.phase, 'desktop');
    expect(loaded.bootCount, 7);
    expect(loaded.tweaks, ['remove_ads', 'cleanup']);
    expect(loaded.wallpaperId, 'ocean');
    expect(loaded.computerName, 'MY-PC');
    expect(loaded.taskbarTheme, 'blue');
    expect(loaded.bootPriority, 'hdd');
    expect(loaded.bottomBarHidden, true);
    expect(loaded.installedAt, DateTime(2026, 8, 7, 12, 1));
    await box.close();
  });

  test('MyPcState: старые данные (без персонализации) читаются без краша', () async {
    // Шаг 1: пишем данные СТАРЫМ адаптером — как старая версия приложения.
    Hive.registerAdapter(LegacyMyPcStateAdapter());
    final box = await Hive.openBox<MyPcState>('myPc');
    await box.put(
      'state',
      MyPcState(
        phase: 'setup',
        setupStage: 1,
        setupProgress: 42.5,
        tweaks: ['compact'],
        bootCount: 3,
      ),
    );
    await box.close();

    // Шаг 2: открываем НОВЫМ адаптером — как обновлённая версия.
    Hive.resetAdapters();
    Hive.registerAdapter(MyPcStateAdapter());
    final box2 = await Hive.openBox<MyPcState>('myPc');
    final loaded = box2.get('state')!;
    expect(loaded.phase, 'setup');
    expect(loaded.setupStage, 1);
    expect(loaded.setupProgress, 42.5);
    expect(loaded.bootCount, 3);
    // Персонализация получает значения по умолчанию.
    expect(loaded.wallpaperId, 'bloom');
    expect(loaded.computerName, 'HERMES-01');
    expect(loaded.taskbarTheme, 'light');
    expect(loaded.bootPriority, 'dvd');
    expect(loaded.bottomBarHidden, false);
    await box2.close();
  });

  test('MyPcState: персонализация без bootPriority читается без краша', () async {
    Hive.registerAdapter(MidMyPcStateAdapter());
    final box = await Hive.openBox<MyPcState>('myPc');
    await box.put(
      'state',
      MyPcState(
        wallpaperId: 'sunset',
        computerName: 'OLD-PC',
        taskbarTheme: 'light',
      ),
    );
    await box.close();

    Hive.resetAdapters();
    Hive.registerAdapter(MyPcStateAdapter());
    final box2 = await Hive.openBox<MyPcState>('myPc');
    final loaded = box2.get('state')!;
    expect(loaded.wallpaperId, 'sunset');
    expect(loaded.computerName, 'OLD-PC');
    expect(loaded.taskbarTheme, 'light');
    expect(loaded.bootPriority, 'dvd');
    await box2.close();
  });

  test('VirtualFsFile: round-trip', () async {
    Hive.registerAdapter(VirtualFsFileAdapter());
    final box = await Hive.openBox<VirtualFsFile>('myPcFiles');
    const file = VirtualFsFile(
      path: r'C:\Users\Hermes\Desktop\Привет.txt',
      content: 'привет мир',
    );
    await box.put('file', file);
    final loaded = box.get('file')!;
    expect(loaded.path, r'C:\Users\Hermes\Desktop\Привет.txt');
    expect(loaded.content, 'привет мир');
    expect(loaded.isFolder, false);
    expect(loaded.name, 'Привет.txt');
    expect(loaded.recycled, false);
    await box.close();
  });

  test('VirtualFsFile: корзина (originalPath) round-trip', () async {
    Hive.registerAdapter(VirtualFsFileAdapter());
    final box = await Hive.openBox<VirtualFsFile>('myPcFiles');
    const recycled = VirtualFsFile(
      path: r'C:\$Recycle.Bin\Привет.txt',
      content: 'привет мир',
      originalPath: r'C:\Users\Hermes\Desktop\Привет.txt',
    );
    await box.put('file', recycled);
    final loaded = box.get('file')!;
    expect(loaded.recycled, true);
    expect(loaded.originalPath, r'C:\Users\Hermes\Desktop\Привет.txt');
    await box.close();
  });

  test('registerHiveAdapters: регистрируются без ошибок', () {
    Hive.resetAdapters();
    expect(registerHiveAdapters, returnsNormally);
  });
}
