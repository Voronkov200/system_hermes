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
    writer
      ..writeInt(obj.tweaks.length)
      ..writeStringList(obj.tweaks)
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

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hermes_hive_test');
    Hive.init(tempDir.path);
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
    );
    await box.put('state', state);
    final loaded = box.get('state')!;
    expect(loaded.phase, 'desktop');
    expect(loaded.bootCount, 7);
    expect(loaded.tweaks, ['remove_ads', 'cleanup']);
    expect(loaded.wallpaperId, 'ocean');
    expect(loaded.computerName, 'MY-PC');
    expect(loaded.taskbarTheme, 'blue');
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
    expect(loaded.wallpaperId, 'default');
    expect(loaded.computerName, 'HERMES-01');
    expect(loaded.taskbarTheme, 'dark');
    await box2.close();
  });

  test('VirtualFsFile: round-trip', () async {
    Hive.registerAdapter(VirtualFsFileAdapter());
    final box = await Hive.openBox<VirtualFsFile>('myPcFiles');
    final file = VirtualFsFile(
      path: r'C:\Users\Hermes\Desktop\Привет.txt',
      content: 'привет мир',
    );
    await box.put('file', file);
    final loaded = box.get('file')!;
    expect(loaded.path, r'C:\Users\Hermes\Desktop\Привет.txt');
    expect(loaded.content, 'привет мир');
    expect(loaded.isFolder, false);
    expect(loaded.name, 'Привет.txt');
    await box.close();
  });

  test('registerHiveAdapters: регистрируются без ошибок', () {
    Hive.resetAdapters();
    expect(registerHiveAdapters, returnsNormally);
  });
}
