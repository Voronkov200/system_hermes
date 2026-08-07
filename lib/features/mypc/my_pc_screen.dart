// Вкладка "Мой ПК": виртуальный компьютер.
//
// Фазы: off -> post -> (bios_setup) -> setup | desktop -> reboot.
// Рабочий стол: оконный менеджер с несколькими окнами, меню Пуск,
// проводник с Корзиной и терминал с историей команд.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/mining_service.dart';
import '../../services/my_pc_service.dart';

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${_fmtTime(d)}';

/// Пресеты обоев рабочего стола (персонализация).
class WallpaperPresets {
  WallpaperPresets._();

  static const ids = ['default', 'ocean', 'forest', 'sunset', 'matrix'];

  static const List<({String id, String name, List<Color> colors})> all = [
    (
      id: 'default',
      name: 'Hermes Night',
      colors: [Color(0xFF0B2E59), Color(0xFF122F5A), Color(0xFF3E2C63), Color(0xFF701F4E)],
    ),
    (
      id: 'ocean',
      name: 'Океан',
      colors: [Color(0xFF0D47A1), Color(0xFF0277BD), Color(0xFF00838F), Color(0xFF00695C)],
    ),
    (
      id: 'forest',
      name: 'Лес',
      colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF33691E), Color(0xFF004D40)],
    ),
    (
      id: 'sunset',
      name: 'Закат',
      colors: [Color(0xFF4A148C), Color(0xFFAD1457), Color(0xFFE65100), Color(0xFFF9A825)],
    ),
    (
      id: 'matrix',
      name: 'Матрица',
      colors: [Color(0xFF000000), Color(0xFF003300), Color(0xFF006600), Color(0xFF00B33C)],
    ),
  ];

  static List<Color> colorsFor(String id) {
    for (final p in all) {
      if (p.id == id) return p.colors;
    }
    return all.first.colors;
  }

  static String nameFor(String id) {
    for (final p in all) {
      if (p.id == id) return p.name;
    }
    return all.first.name;
  }
}

class MyPcScreen extends ConsumerStatefulWidget {
  const MyPcScreen({super.key});

  @override
  ConsumerState<MyPcScreen> createState() => _MyPcScreenState();
}

class _MyPcScreenState extends ConsumerState<MyPcScreen> {
  Timer? _timer;
  final List<_Win> _windows = [];
  int _nextId = 1;
  int _z = 0;
  bool _startOpen = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(myPcProvider.notifier).tick();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const int maxWindows = 5;

  void _open(_WinType type, {String? path, String? filePath}) {
    if (_windows.length >= maxWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Слишком много окон — закройте одно.')),
      );
      return;
    }
    final w = _Win(id: _nextId++, type: type, path: path, filePath: filePath);
    w.pos = Offset(
      24 + (_windows.length % 4) * 18,
      16 + (_windows.length % 4) * 14,
    );
    _windows.add(w);
    _focus(w);
  }

  void _focus(_Win w) {
    w.z = ++_z;
    w.minimized = false;
    setState(() => _startOpen = false);
  }

  void _toggleMinimize(_Win w) {
    setState(() => w.minimized = !w.minimized);
  }

  void _close(_Win w) {
    setState(() => _windows.remove(w));
  }

  void _shutdown() {
    setState(() {
      _windows.clear();
      _startOpen = false;
    });
    ref.read(myPcProvider.notifier).shutdown();
  }

  @override
  Widget build(BuildContext context) {
    final pc = ref.watch(myPcProvider);
    final phase = pc.state.phase;
    final isOff = phase == 'off';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: _MonitorFrame(
                  child: switch (phase) {
                    'off' => const _OffScreen(),
                    'post' => _PostScreen(state: pc.state),
                    'bios_setup' => _BiosSetupScreen(state: pc.state),
                    'setup' => _SetupScreen(state: pc.state),
                    'reboot' => const _RebootScreen(),
                    _ => _DesktopScreen(
                        state: pc.state,
                        files: pc.files,
                        windows: _windows,
                        startOpen: _startOpen,
                        onOpen: _open,
                        onFocus: _focus,
                        onMinimize: _toggleMinimize,
                        onClose: _close,
                        onStartToggle: () =>
                            setState(() => _startOpen = !_startOpen),
                        onShutdown: _shutdown,
                        onReboot: () {
                          setState(() {
                            _windows.clear();
                            _startOpen = false;
                          });
                          ref.read(myPcProvider.notifier).reboot();
                        },
                      ),
                  },
                ),
              ),
            ),
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              color: AppColors.surface,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (phase) {
                        'off' => 'ПК выключен',
                        'post' => 'Включение...',
                        'bios_setup' => 'BIOS Setup',
                        'setup' => 'Установка Windows',
                        'reboot' => 'Перезагрузка...',
                        _ => 'Windows 11 Pro — работает',
                      },
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: isOff ? 'Включить' : 'Выключить',
                    onPressed: () => isOff
                        ? ref.read(myPcProvider.notifier).powerOn()
                        : _shutdown(),
                    icon: Icon(
                      isOff ? Icons.power_settings_new : Icons.power_off,
                      color: isOff ? AppColors.accent : AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Перезагрузить',
                    onPressed: isOff
                        ? null
                        : () {
                            setState(() {
                              _windows.clear();
                              _startOpen = false;
                            });
                            ref.read(myPcProvider.notifier).reboot();
                          },
                    icon: const Icon(Icons.restart_alt,
                        color: AppColors.warning),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// МОНИТОР (рамка)
// =====================================================================

class _MonitorFrame extends StatelessWidget {
  final Widget child;

  const _MonitorFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E24),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

// =====================================================================
// ВЫКЛЮЧЕН
// =====================================================================

class _OffScreen extends ConsumerWidget {
  const _OffScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: const Color(0xFF1A222E),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => ref.read(myPcProvider.notifier).powerOn(),
                child: const Padding(
                  padding: EdgeInsets.all(28),
                  child: Icon(
                    Icons.power_settings_new,
                    size: 64,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Нажмите кнопку питания',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 17,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Будет установлена: ${VirtualFsCatalog.esdFileName.replaceAll('.esd', '')}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// POST (самотестирование при включении)
// =====================================================================

class _PostScreen extends ConsumerWidget {
  final MyPcState state;

  const _PostScreen({required this.state});

  String get _bootLabel => switch (state.bootPriority) {
        'hdd' => 'Жёсткий диск (C:)',
        'usb' => 'USB Flash',
        _ => 'DVD-ROM (${VirtualFsCatalog.esdFileName})',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specs = _specsOf(ref);
    final firstInstall = state.installedAt == null &&
        (state.bootPriority == 'dvd' || state.bootPriority == 'usb');
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                [
                  'Hermes BIOS v2.5.1 (Build 08/2026)',
                  'Copyright (C) 2026 Hermes Systems',
                  '',
                  'CPU  : ${specs['CPU']}',
                  'Memory: ${specs['RAM']} OK',
                  'SATA : ${specs['Storage']}',
                  'Boot : $_bootLabel',
                  '',
                  'Press DEL to enter BIOS Setup...',
                  if (firstInstall)
                    'Press any key to boot from installation media...',
                ].join('\n'),
                style: const TextStyle(
                  color: Color(0xFF33FF66),
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: Material(
              color: const Color(0xFF003300),
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => ref.read(myPcProvider.notifier).enterBiosSetup(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Text(
                    'DEL  →  BIOS Setup',
                    style: TextStyle(
                      color: Color(0xFF33FF66),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// BIOS SETUP (интерактивный)
// =====================================================================

class _BiosSetupScreen extends ConsumerStatefulWidget {
  final MyPcState state;

  const _BiosSetupScreen({required this.state});

  @override
  ConsumerState<_BiosSetupScreen> createState() => _BiosSetupScreenState();
}

class _BiosSetupScreenState extends ConsumerState<_BiosSetupScreen> {
  int _tab = 0; // 0 = Main, 1 = Boot, 2 = Exit
  late String _selectedBoot;

  static const _tabs = ['Main', 'Boot', 'Exit'];
  static const _bootNames = {
    'dvd': 'DVD-ROM (установочный диск)',
    'hdd': 'Жёсткий диск (C:)',
    'usb': 'USB Flash',
  };

  @override
  void initState() {
    super.initState();
    _selectedBoot = widget.state.bootPriority;
  }

  @override
  Widget build(BuildContext context) {
    final specs = _specsOf(ref);
    final isLight = _tab == 0 || _tab == 1;
    final bg = isLight ? const Color(0xFFE8E8E8) : const Color(0xFF404040);
    final textColor = isLight ? Colors.black87 : Colors.white;
    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF003366),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'HERMES BIOS Setup Utility',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  'v2.5.1',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: bg,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 88,
                    color: const Color(0xFFC8C8C8),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        for (var i = 0; i < _tabs.length; i++)
                          _BiosTabButton(
                            label: _tabs[i],
                            selected: _tab == i,
                            onTap: () => setState(() => _tab = i),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: switch (_tab) {
                        0 => _buildMain(specs, textColor),
                        1 => _buildBoot(textColor),
                        _ => _buildExit(),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: const Color(0xFF2E2E2E),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text(
              '↑↓ Выбор   F10 Сохранить и выйти   ESC Выйти без сохранения',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain(Map<String, String> specs, Color textColor) {
    final s = widget.state;
    return ListView(
      children: [
        for (final (k, v) in [
          ('CPU Type', specs['CPU']!),
          ('Memory', specs['RAM']!),
          ('SATA Port 1', specs['Storage']!),
          ('OS', s.installedAt == null ? 'Не установлена' : s.osName),
          ('Computer Name', s.computerName),
          ('Boot Count', '${s.bootCount}'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    k,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    v,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(
          'Системная дата: ${_fmtDateTime(DateTime.now())}',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.6),
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildBoot(Color textColor) {
    return ListView(
      children: [
        Text(
          'Приоритет загрузки (1 — первый):',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.7),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in _bootNames.entries)
          _BiosBootItem(
            title: entry.value,
            selected: _selectedBoot == entry.key,
            onTap: () => setState(() => _selectedBoot = entry.key),
          ),
        const SizedBox(height: 10),
        Text(
          'Изменения применяются при выборе «Сохранить и выйти».',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.5),
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildExit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BiosActionButton(
          label: 'Сохранить изменения и выйти',
          accent: true,
          onTap: () {
            ref.read(myPcProvider.notifier).setBootPriority(_selectedBoot);
            ref.read(myPcProvider.notifier).exitBiosSetup(save: true);
          },
        ),
        const SizedBox(height: 8),
        _BiosActionButton(
          label: 'Выйти без сохранения',
          onTap: () =>
              ref.read(myPcProvider.notifier).exitBiosSetup(save: false),
        ),
      ],
    );
  }
}

class _BiosTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BiosTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        color: selected ? const Color(0xFF2E2E2E) : null,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

class _BiosBootItem extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _BiosBootItem({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF005DA6) : const Color(0xFFDCDCDC),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: selected ? Colors.white : Colors.black45,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BiosActionButton extends StatelessWidget {
  final String label;
  final bool accent;
  final VoidCallback onTap;

  const _BiosActionButton({
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent ? const Color(0xFF0067C0) : const Color(0xFFDCDCDC),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent ? Colors.white : Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// УСТАНОВКА WINDOWS
// =====================================================================

class _SetupScreen extends StatelessWidget {
  final MyPcState state;

  const _SetupScreen({required this.state});

  static const _stages = [
    'Копирование файлов Windows',
    'Установка компонентов',
    'Установка обновлений',
    'Завершение установки',
  ];

  @override
  Widget build(BuildContext context) {
    final stage = state.setupStage.clamp(0, 3);
    final progress = state.setupProgress.clamp(0.0, 100.0).toDouble();
    final copied = progress / 100 * state.imageSizeGb;
    return ColoredBox(
      color: const Color(0xFF0067C0),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(0, -0.6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _WindowsLogo(size: 96),
                const SizedBox(height: 24),
                Text(
                  'Установка Windows',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  state.osName,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.75),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stages[stage],
                    style: const TextStyle(color: Colors.white, fontSize: 17),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    stage == 0
                        ? 'Скопировано: ${copied.toStringAsFixed(1)} ГБ из ${state.imageSizeGb.toStringAsFixed(1)} ГБ'
                        : 'Установка: ${progress.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 16,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor:
                          const AlwaysStoppedAnimation(Color(0xFFF2F2F2)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Логотип Windows: 4 квадрата.
class _WindowsLogo extends StatelessWidget {
  final double size;

  const _WindowsLogo({this.size = 32});

  @override
  Widget build(BuildContext context) {
    final cell = size / 2;
    return SizedBox(
      width: size,
      height: size,
      child: GridView.count(
        crossAxisCount: 2,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _cell(Colors.white, cell),
          _cell(Colors.white, cell),
          _cell(Colors.white, cell),
          _cell(Colors.white, cell),
        ],
      ),
    );
  }

  Widget _cell(Color color, double cell) {
    return Container(
      margin: EdgeInsets.all(cell * 0.04),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(cell * 0.18),
      ),
    );
  }
}

// =====================================================================
// ПЕРЕЗАГРУЗКА
// =====================================================================

class _RebootScreen extends StatelessWidget {
  const _RebootScreen();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          'Перезагрузка...',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// ОКНА
// =====================================================================

enum _WinType { notepad, browser, explorer, terminal, about, personalize, properties }

class _Win {
  _Win({required this.id, required this.type, this.path, this.filePath});

  final int id;
  final _WinType type;

  /// Проводник: текущий каталог; свойства: целевой файл.
  String? path;

  /// Блокнот: файл; URL браузера.
  String? filePath;

  String url = 'https://www.google.com';
  Offset pos = const Offset(24, 16);
  bool minimized = false;
  int z = 0;

  Size sizeFor() => switch (type) {
        _WinType.browser => const Size(348, 380),
        _WinType.explorer => const Size(348, 360),
        _WinType.terminal => const Size(348, 330),
        _WinType.notepad => const Size(330, 340),
        _WinType.personalize => const Size(350, 400),
        _WinType.about => const Size(340, 360),
        _WinType.properties => const Size(310, 260),
      };

  String titleFor() {
    switch (type) {
      case _WinType.notepad:
        return filePath == null ? 'Блокнот' : 'Блокнот — ${_baseName(filePath!)}';
      case _WinType.browser:
        return 'Браузер';
      case _WinType.explorer:
        return path == VirtualFsCatalog.recycleBinPath ? 'Корзина' : 'Компьютер';
      case _WinType.terminal:
        return 'Командная строка';
      case _WinType.personalize:
        return 'Персонализация';
      case _WinType.about:
        return 'Об этом ПК';
      case _WinType.properties:
        return path == null ? 'Свойства' : 'Свойства: ${_baseName(path!)}';
    }
  }

  static String _baseName(String p) {
    final i = p.lastIndexOf(r'\');
    return i < 0 ? p : p.substring(i + 1);
  }
}

// =====================================================================
// РАБОЧИЙ СТОЛ
// =====================================================================

class _DesktopScreen extends ConsumerWidget {
  final MyPcState state;
  final List<VirtualFsFile> files;
  final List<_Win> windows;
  final bool startOpen;
  final void Function(_WinType, {String? path, String? filePath}) onOpen;
  final ValueChanged<_Win> onFocus;
  final ValueChanged<_Win> onMinimize;
  final ValueChanged<_Win> onClose;
  final VoidCallback onStartToggle;
  final VoidCallback onShutdown;
  final VoidCallback onReboot;

  const _DesktopScreen({
    required this.state,
    required this.files,
    required this.windows,
    required this.startOpen,
    required this.onOpen,
    required this.onFocus,
    required this.onMinimize,
    required this.onClose,
    required this.onStartToggle,
    required this.onShutdown,
    required this.onReboot,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WallpaperPresets.colorsFor(state.wallpaperId);
    final theme = state.taskbarTheme;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final area = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: colors,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _DesktopIcons(
                      state: state,
                      files: files,
                      onOpen: onOpen,
                    ),
                  ),
                  for (final w in windows)
                    Positioned(
                      left: w.pos.dx.clamp(0.0, area.width - 120),
                      top: w.pos.dy.clamp(0.0, area.height - 80),
                      width: w.sizeFor().width.clamp(200.0, area.width - 20),
                      height: w.sizeFor().height.clamp(180.0, area.height - 20),
                      child: Offstage(
                        offstage: w.minimized,
                        child: _WindowFrame(
                          win: w,
                          isFocused: w.z == _maxZ(windows),
                          onTap: () => onFocus(w),
                          onDrag: (delta) {
                            final size = w.sizeFor();
                            final nx = (w.pos.dx + delta.dx)
                                .clamp(0.0, area.width - size.width);
                            final ny = (w.pos.dy + delta.dy)
                                .clamp(0.0, area.height - size.height);
                            w.pos = Offset(nx, ny);
                          },
                          onMinimize: () => onMinimize(w),
                          onClose: () => onClose(w),
                          content: _windowContent(w),
                        ),
                      ),
                    ),
                  if (startOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: onStartToggle,
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  if (startOpen)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _StartMenu(
                        theme: theme,
                        onClose: onStartToggle,
                        onOpen: (type, path, filePath) {
                          onOpen(type, path: path, filePath: filePath);
                        },
                        onShutdown: onShutdown,
                        onReboot: onReboot,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        _Taskbar(
          theme: theme,
          startMenuOpen: startOpen,
          onStart: onStartToggle,
          windows: windows,
          onWindowTap: (w) =>
              w.minimized ? onFocus(w) : onMinimize(w),
        ),
      ],
    );
  }

  static int _maxZ(List<_Win> ws) =>
      ws.fold(0, (m, w) => w.z > m ? w.z : m);

  Widget _windowContent(_Win w) {
    switch (w.type) {
      case _WinType.notepad:
        return _NotepadWindow(key: ValueKey('np${w.id}'), filePath: w.filePath);
      case _WinType.browser:
        return _BrowserWindow(
          key: ValueKey('br${w.id}'),
          initialUrl: w.url,
          onUrlChange: (u) => w.url = u,
        );
      case _WinType.explorer:
        return _ExplorerWindow(
          key: ValueKey('ex${w.id}'),
          path: w.path ?? r'C:\',
          onOpen: onOpen,
        );
      case _WinType.terminal:
        return _TerminalWindow(
          key: ValueKey('tm${w.id}'),
          onOpen: onOpen,
        );
      case _WinType.personalize:
        return const _PersonalizeWindow();
      case _WinType.about:
        return const _AboutWindow();
      case _WinType.properties:
        return _PropertiesWindow(path: w.path!);
    }
  }
}

class _DesktopIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _DesktopIcon({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 78,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopIcons extends StatelessWidget {
  final MyPcState state;
  final List<VirtualFsFile> files;
  final void Function(_WinType, {String? path, String? filePath}) onOpen;

  const _DesktopIcons({
    required this.state,
    required this.files,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final recycleCount = files
        .where((f) =>
            f.recycled && f.parent == VirtualFsCatalog.recycleBinPath)
        .length;
    final desktop = files
        .where((f) =>
            f.parent == r'C:\Users\Hermes\Desktop' && !f.recycled)
        .toList();
    return SingleChildScrollView(
      child: Column(
        children: [
          _DesktopIcon(
            icon: Icons.public,
            color: const Color(0xFF64B5F6),
            label: 'Браузер',
            onTap: () => onOpen(_WinType.browser),
          ),
          _DesktopIcon(
            icon: Icons.folder,
            color: const Color(0xFFF2B33D),
            label: 'Компьютер',
            onTap: () => onOpen(_WinType.explorer),
          ),
          _DesktopIcon(
            icon: Icons.terminal,
            color: const Color(0xFF9E9E9E),
            label: 'Терминал',
            onTap: () => onOpen(_WinType.terminal),
          ),
          _DesktopIcon(
            icon: Icons.description_outlined,
            color: const Color(0xFF90A4AE),
            label: 'Блокнот',
            onTap: () {
              const path = r'C:\Users\Hermes\Desktop\Новый текстовый документ.txt';
              onOpen(_WinType.notepad, filePath: path);
            },
          ),
          _DesktopIcon(
            icon: Icons.delete_outline,
            color: const Color(0xFFB0BEC5),
            label: recycleCount > 0 ? 'Корзина ($recycleCount)' : 'Корзина',
            onTap: () => onOpen(
              _WinType.explorer,
              path: VirtualFsCatalog.recycleBinPath,
            ),
          ),
          _DesktopIcon(
            icon: Icons.palette_outlined,
            color: const Color(0xFFCE93D8),
            label: 'Персонализация',
            onTap: () => onOpen(_WinType.personalize),
          ),
          _DesktopIcon(
            icon: Icons.info_outline,
            color: const Color(0xFF81C784),
            label: 'Об этом ПК',
            onTap: () => onOpen(_WinType.about),
          ),
          const SizedBox(height: 10),
          for (final f in desktop)
            _DesktopIcon(
              icon: _iconForFile(f),
              color: f.isFolder
                  ? const Color(0xFFF2B33D)
                  : Colors.blueGrey,
              label: f.name,
              onTap: () {
                if (f.isFolder) {
                  onOpen(_WinType.explorer, path: f.path);
                  return;
                }
                if (f.name.endsWith('.txt')) {
                  onOpen(_WinType.notepad, filePath: f.path);
                } else {
                  onOpen(_WinType.properties, path: f.path);
                }
              },
            ),
        ],
      ),
    );
  }

  static IconData _iconForFile(VirtualFsFile f) {
    if (f.isFolder) return Icons.folder;
    final n = f.name.toLowerCase();
    if (n.endsWith('.txt')) return Icons.description_outlined;
    if (n.endsWith('.esd')) return Icons.archive_outlined;
    if (n.endsWith('.exe')) return Icons.settings_applications;
    return Icons.insert_drive_file;
  }
}

// =====================================================================
// РАМКА ОКНА
// =====================================================================

class _WindowFrame extends StatelessWidget {
  final _Win win;
  final bool isFocused;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final Widget content;

  const _WindowFrame({
    required this.win,
    required this.isFocused,
    required this.onTap,
    required this.onDrag,
    required this.onMinimize,
    required this.onClose,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isFocused ? 0.45 : 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: (d) => onDrag(d.delta),
              child: Container(
                height: 30,
                color: isFocused
                    ? const Color(0xFF00458A)
                    : const Color(0xFF8A8A8A),
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    Icon(_titleIcon(), size: 14, color: Colors.white70),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        win.titleFor(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onMinimize,
                      child: const SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(Icons.remove, size: 16, color: Colors.white),
                      ),
                    ),
                    InkWell(
                      onTap: onClose,
                      child: const SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(Icons.close, size: 15, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  IconData _titleIcon() => switch (win.type) {
        _WinType.notepad => Icons.description_outlined,
        _WinType.browser => Icons.public,
        _WinType.explorer =>
          win.path == VirtualFsCatalog.recycleBinPath
              ? Icons.delete_outline
              : Icons.computer,
        _WinType.terminal => Icons.terminal,
        _WinType.personalize => Icons.palette_outlined,
        _WinType.about => Icons.info_outline,
        _WinType.properties => Icons.tune,
      };
}

// =====================================================================
// БЛОКНОТ
// =====================================================================

class _NotepadWindow extends ConsumerStatefulWidget {
  final String? filePath;

  const _NotepadWindow({super.key, this.filePath});

  @override
  ConsumerState<_NotepadWindow> createState() => _NotepadWindowState();
}

class _NotepadWindowState extends ConsumerState<_NotepadWindow> {
  late final TextEditingController _ctrl;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    final f = widget.filePath == null
        ? null
        : ref.read(myPcProvider.notifier).fileAt(widget.filePath!);
    _ctrl = TextEditingController(text: f?.content ?? '');
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleSave(String text) {
    final path = widget.filePath;
    if (path == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(myPcProvider.notifier).writeFile(path, text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: TextField(
        controller: _ctrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Colors.black87,
        ),
        onChanged: _scheduleSave,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(10),
        ),
      ),
    );
  }
}

// =====================================================================
// БРАУЗЕР
// =====================================================================

class _BrowserWindow extends StatefulWidget {
  final String initialUrl;
  final ValueChanged<String> onUrlChange;

  const _BrowserWindow({
    super.key,
    required this.initialUrl,
    required this.onUrlChange,
  });

  @override
  State<_BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends State<_BrowserWindow> {
  late final WebViewController _controller;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialUrl);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) => widget.onUrlChange(url),
        ),
      );
    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _go(String url) {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    _urlCtrl.text = u;
    widget.onUrlChange(u);
    _controller.loadRequest(Uri.parse(u));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F3F3),
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: () => _controller.goBack(),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  onPressed: () => _controller.goForward(),
                ),
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    onSubmitted: _go,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => _controller.reload(),
                ),
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// ПРОВОДНИК
// =====================================================================

class _ExplorerWindow extends ConsumerStatefulWidget {
  final String path;
  final void Function(_WinType, {String? path, String? filePath}) onOpen;

  const _ExplorerWindow({super.key, required this.path, required this.onOpen});

  @override
  ConsumerState<_ExplorerWindow> createState() => _ExplorerWindowState();
}

class _ExplorerWindowState extends ConsumerState<_ExplorerWindow> {
  late String _path;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _path = widget.path;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _inRecycle => _path == VirtualFsCatalog.recycleBinPath;

  void _open(String path) {
    final f = ref.read(myPcProvider.notifier).fileAt(path);
    if (f == null) return;
    if (f.isFolder) {
      setState(() => _path = path);
      return;
    }
    if (f.name.toLowerCase().endsWith('.txt')) {
      widget.onOpen(_WinType.notepad, filePath: path);
    } else {
      widget.onOpen(_WinType.properties, path: path);
    }
  }

  void _newFolder() async {
    final name = await _askName('Имя новой папки');
    if (name == null || name.trim().isEmpty) return;
    final err = ref
        .read(myPcProvider.notifier)
        .createFolder('$_path\\${name.trim()}');
    if (err != null) _toast(err);
  }

  void _newFile() async {
    final name = await _askName('Имя нового файла (.txt)');
    if (name == null || name.trim().isEmpty) return;
    final fname =
        name.trim().endsWith('.txt') ? name.trim() : '${name.trim()}.txt';
    final ctrl = ref.read(myPcProvider.notifier);
    if (ctrl.fileAt('$_path\\$fname') != null) {
      _toast('Файл уже существует');
      return;
    }
    ctrl.writeFile('$_path\\$fname', '');
  }

  void _rename(String path) async {
    final f = ref.read(myPcProvider.notifier).fileAt(path);
    if (f == null) return;
    final name = await _askName('Новое имя', initial: f.name);
    if (name == null || name.trim().isEmpty) return;
    final err =
        ref.read(myPcProvider.notifier).renameFile(path, name.trim());
    if (err != null) _toast(err);
  }

  void _delete(String path) async {
    final f = ref.read(myPcProvider.notifier).fileAt(path);
    if (f == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(f.isFolder ? 'Удалить папку?' : 'Удалить файл?'),
        content: Text('«${f.name}» будет перемещён в Корзину.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(myPcProvider.notifier).moveToRecycle(path);
    }
  }

  void _restore(String path) async {
    final err =
        ref.read(myPcProvider.notifier).restoreFromRecycle(path);
    if (err != null) _toast(err);
  }

  void _purge(String path) {
    ref.read(myPcProvider.notifier).purgeFromRecycle(path);
  }

  void _props(String path) {
    widget.onOpen(_WinType.properties, path: path);
  }

  Future<String?> _askName(String title, {String? initial}) {
    _nameCtrl.text = initial ?? '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: _nameCtrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _nameCtrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(myPcProvider.notifier);
    final items = ctrl.listDir(_path);
    final isRoot = _path == r'C:\';
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF5F5F5),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Назад',
                  onPressed: isRoot
                      ? null
                      : () {
                          final p = _path.lastIndexOf(r'\');
                          setState(() => _path = p <= 2
                              ? r'C:\'
                              : _path.substring(0, p));
                        },
                  icon: const Icon(Icons.arrow_upward, size: 16),
                ),
                Expanded(
                  child: Text(
                    _path,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!_inRecycle)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Новая папка',
                    onPressed: _newFolder,
                    icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                  ),
                if (!_inRecycle)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Новый файл',
                    onPressed: _newFile,
                    icon: const Icon(Icons.note_add_outlined, size: 16),
                  ),
              ],
            ),
          ),
          if (_inRecycle)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF8E1),
              padding: const EdgeInsets.all(6),
              child: const Text(
                'Корзина: здесь лежат удалённые файлы. Восстановите или удалите навсегда.',
                style: TextStyle(fontSize: 10, color: Color(0xFF8D6E00)),
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'Папка пуста',
                      style: TextStyle(fontSize: 12, color: Colors.black38),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final f = items[i];
                      return InkWell(
                        onTap: () => _inRecycle ? null : _open(f.path),
                        onLongPress: () => _inRecycle
                            ? _showRecycleActions(f)
                            : _showActions(f),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                _fileIcon(f),
                                size: 22,
                                color: f.isFolder
                                    ? const Color(0xFFF2B33D)
                                    : Colors.blueGrey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _inRecycle ? f.originalPath ?? f.name : f.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (f.isFolder)
                                const Icon(Icons.chevron_right,
                                    size: 16, color: Colors.black26),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showActions(VirtualFsFile f) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Открыть'),
              onTap: () {
                Navigator.pop(context);
                _open(f.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Переименовать'),
              onTap: () {
                Navigator.pop(context);
                _rename(f.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Свойства'),
              onTap: () {
                Navigator.pop(context);
                _props(f.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Удалить (в Корзину)'),
              onTap: () {
                Navigator.pop(context);
                _delete(f.path);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRecycleActions(VirtualFsFile f) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.green),
              title: const Text('Восстановить'),
              onTap: () {
                Navigator.pop(context);
                _restore(f.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Удалить навсегда'),
              onTap: () {
                Navigator.pop(context);
                _purge(f.path);
              },
            ),
          ],
        ),
      ),
    );
  }

  static IconData _fileIcon(VirtualFsFile f) {
    if (f.isFolder) return Icons.folder;
    final n = f.name.toLowerCase();
    if (n.endsWith('.txt')) return Icons.description_outlined;
    if (n.endsWith('.esd')) return Icons.archive_outlined;
    if (n.endsWith('.exe')) return Icons.settings_applications;
    return Icons.insert_drive_file;
  }
}

// =====================================================================
// ТЕРМИНАЛ
// =====================================================================

class _TerminalWindow extends ConsumerStatefulWidget {
  final void Function(_WinType, {String? path, String? filePath}) onOpen;

  const _TerminalWindow({super.key, required this.onOpen});

  @override
  ConsumerState<_TerminalWindow> createState() => _TerminalWindowState();
}

class _TerminalWindowState extends ConsumerState<_TerminalWindow> {
  static const _commands = [
    'help', 'dir', 'cd', 'type', 'echo', 'cls', 'ipconfig', 'systeminfo',
    'winver', 'mkdir', 'del', 'notepad', 'explorer', 'start', 'shutdown',
    'reboot',
  ];

  final List<String> _lines = [
    'Microsoft Windows [Версия 10.0.26100]',
    '(c) Hermes Systems. Все права защищены.',
    'Введите help для списка команд.',
  ];
  final List<String> _history = [];
  int _histIndex = -1;
  late final TextEditingController _ctrl;
  final _scrollCtrl = ScrollController();
  String _dir = r'C:\Users\Hermes';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _print(String s) {
    setState(() => _lines.add(s));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  String _prompt() => '$_dir>';

  void _run(String raw) {
    final input = raw.trim();
    _history.add(input);
    _histIndex = -1;
    if (input.isNotEmpty) _print('$_prompt()$input');
    if (input.isEmpty) {
      _print(_prompt());
      return;
    }
    final parts = input.split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();
    final arg = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    if (cmd == 'help') {
      _print('Доступные команды:');
      for (final c in _commands) {
        _print('  $c');
      }
    } else if (cmd == 'dir' || cmd == 'ls') {
      _print(' Содержимое каталога $_dir:');
      final ctrl = ref.read(myPcProvider.notifier);
      final items = ctrl.listDir(_dir);
      if (items.isEmpty) {
        _print('  (пусто)');
      }
      for (final f in items) {
        _print('  ${f.isFolder ? '<DIR>' : '     '}  ${f.name}');
      }
    } else if (cmd == 'cd') {
      if (arg.isEmpty) {
        _print(_dir);
      } else {
        _cd(arg);
      }
    } else if (cmd == 'type') {
      if (arg.isEmpty) {
        _print('Использование: type <файл>');
      } else {
        final ctrl = ref.read(myPcProvider.notifier);
        final f = ctrl.fileAt(_resolve(arg));
        if (f == null) {
          _print('Не удается найти файл: $arg');
        } else if (f.isFolder) {
          _print('$arg — это папка.');
        } else {
          _print(f.content);
        }
      }
    } else if (cmd == 'echo') {
      _print(arg);
    } else if (cmd == 'cls') {
      setState(_lines.clear);
    } else if (cmd == 'ipconfig') {
      _print('Настройка протокола IP для Windows');
      _print('');
      _print('Адаптер Ethernet Ethernet0:');
      _print(
          '   IPv4-адрес. . . . . . : 192.168.1.${(DateTime.now().second % 200) + 10}');
      _print('   Маска подсети . . . . : 255.255.255.0');
      _print('   Основной шлюз. . . . . : 192.168.1.1');
      _print('   DHCP-сервер . . . . . : 192.168.1.1');
    } else if (cmd == 'systeminfo') {
      final specs = _specsOf(ref);
      _print('Имя компьютера: ${ref.read(myPcProvider).state.computerName}');
      _print('ОС: ${ref.read(myPcProvider).state.osName}');
      _print('Процессор: ${specs['CPU']}');
      _print('Видеокарта: ${specs['GPU']}');
      _print('Память: ${specs['RAM']}');
      _print('Накопитель: ${specs['Storage']}');
    } else if (cmd == 'winver') {
      _print('Windows 11 Pro — Hermes Edition');
      _print('Версия 25H2 (сборка ОС 26100.2000)');
    } else if (cmd == 'mkdir') {
      if (arg.isEmpty) {
        _print('Использование: mkdir <папка>');
      } else {
        final err = ref
            .read(myPcProvider.notifier)
            .createFolder(_resolve(arg));
        _print(err ?? 'Папка создана.');
      }
    } else if (cmd == 'del') {
      if (arg.isEmpty) {
        _print('Использование: del <файл>');
      } else {
        _confirmDelete(arg);
      }
    } else if (cmd == 'notepad') {
      if (arg.isEmpty) {
        widget.onOpen(_WinType.notepad, filePath: null);
      } else {
        widget.onOpen(_WinType.notepad, filePath: _resolve(arg));
      }
    } else if (cmd == 'explorer') {
      widget.onOpen(_WinType.explorer);
    } else if (cmd == 'start') {
      _start(arg);
    } else if (cmd == 'shutdown') {
      _confirmPower('Выключить компьютер?', () async {
        final s = ref.read(myPcProvider.notifier);
        s.shutdown();
      });
    } else if (cmd == 'reboot') {
      _confirmPower('Перезагрузить компьютер?', () async {
        final s = ref.read(myPcProvider.notifier);
        s.reboot();
      });
    } else {
      _print(
          "'$cmd' не является внутренней или внешней командой,\nисполняемой программой или пакетным файлом.");
    }
  }

  void _cd(String arg) {
    if (arg == '..') {
      final i = _dir.lastIndexOf(r'\');
      if (i <= 2) {
        _dir = r'C:\';
      } else {
        _dir = _dir.substring(0, i);
      }
      return;
    }
    final target = _resolve(arg);
    final f = ref.read(myPcProvider.notifier).fileAt(target);
    if (f == null || !f.isFolder) {
      _print('Системе не удается найти указанный путь.');
      return;
    }
    _dir = target;
  }

  String _resolve(String name) {
    if (name.contains(r'\') || name.endsWith(':')) {
      return name.length == 2 && name.endsWith(':')
          ? '$name\\'
          : name;
    }
    if (_dir.endsWith(r'\')) return '$_dir$name';
    return '$_dir\\$name';
  }

  void _confirmDelete(String arg) async {
    final ctrl = ref.read(myPcProvider.notifier);
    final f = ctrl.fileAt(_resolve(arg));
    if (f == null) {
      _print('Не удается найти файл: $arg');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(f.isFolder ? 'Удалить папку?' : 'Удалить файл?'),
        content: Text('«${f.name}» будет перемещён в Корзину.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ctrl.moveToRecycle(f.path);
      _print('Удалено: ${f.name} (в Корзине)');
    } else {
      _print('Операция отменена.');
    }
  }

  void _start(String arg) {
    final lower = arg.toLowerCase();
    if (lower.contains('gpu_driver')) {
      _print('Установка драйвера видеокарты...');
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        final farm = ref.read(miningProvider).farm;
        if (farm.driversInstalled) {
          _print('Драйвер уже установлен.');
          return;
        }
        ref.read(miningProvider.notifier).installDrivers();
        _print('Драйвер NVIDIA установлен. Ферма: полная мощность.');
        _toast('Драйверы установлены — хешрейт фермы без ограничений.');
      });
      return;
    }
    if (arg.isEmpty) {
      _print('Использование: start <программа или файл>');
      return;
    }
    final f = ref.read(myPcProvider.notifier).fileAt(_resolve(arg));
    if (f == null) {
      _print('Не удается найти файл: $arg');
      return;
    }
    if (f.name.toLowerCase().endsWith('.txt')) {
      widget.onOpen(_WinType.notepad, filePath: f.path);
    } else {
      _print('Запуск «${f.name}»... (нет обработчика)');
    }
  }

  void _confirmPower(String question, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (ok == true) await action();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _autocomplete() {
    final text = _ctrl.text;
    final lastSpace = text.lastIndexOf(' ');
    final prefix = lastSpace < 0 ? '' : text.substring(0, lastSpace + 1);
    final token = lastSpace < 0 ? text : text.substring(lastSpace + 1);
    final t = token.toLowerCase();
    if (lastSpace < 0) {
      final matches = _commands.where((c) => c.startsWith(t)).toList();
      if (matches.length == 1) {
        _ctrl.text = '${matches.first} ';
        _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
        return;
      }
      if (matches.length > 1) {
        _print('Команды: ${matches.join(', ')}');
      }
      return;
    }
    final dirItems = ref
        .read(myPcProvider.notifier)
        .listDir(_dir)
        .map((f) => f.isFolder ? f.name + r'\' : f.name)
        .where((n) => n.toLowerCase().startsWith(t))
        .toList();
    if (dirItems.length == 1) {
      _ctrl.text = '$prefix${dirItems.first}';
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    } else if (dirItems.length > 1) {
      _print('Элементы: ${dirItems.join(', ')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(8),
              itemCount: _lines.length,
              itemBuilder: (context, i) => SelectableText(
                _lines[i],
                style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ),
          Container(
            color: const Color(0xFF1E1E1E),
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: Row(
              children: [
                Text(
                  _prompt(),
                  style: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(
                      color: Color(0xFFCCCCCC),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    onSubmitted: (v) {
                      _run(v);
                      _ctrl.clear();
                    },
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                InkWell(
                  onTap: _historyBack,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.keyboard_arrow_up,
                        size: 16, color: Color(0xFF8A8A8A)),
                  ),
                ),
                InkWell(
                  onTap: _autocomplete,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Text(
                      'Tab',
                      style: TextStyle(
                        color: Color(0xFF8A8A8A),
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _historyBack() {
    if (_history.isEmpty) return;
    _histIndex = _histIndex < 0 ? _history.length - 1 : _histIndex - 1;
    if (_histIndex < 0) _histIndex = 0;
    _ctrl.text = _history[_histIndex];
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    setState(() {});
  }
}

// =====================================================================
// ОБ ЭТОМ ПК
// =====================================================================

class _AboutWindow extends ConsumerWidget {
  const _AboutWindow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myPcProvider).state;
    final specs = _specsOf(ref);
    final rows = <(String, String)>[
      ('Имя компьютера', state.computerName),
      ('Процессор', specs['CPU']!),
      ('Видеокарта', specs['GPU']!),
      ('Память', specs['RAM']!),
      ('Накопитель', specs['Storage']!),
      ('ОС', state.osName),
      ('Редакция', state.edition),
      ('Сборка ОС', '26100.2000 (25H2, RU)'),
      ('Образ', 'install.esd, ${state.imageSizeGb.toStringAsFixed(1)} ГБ'),
      ('Установлена', state.installedAt == null
          ? '—'
          : _fmtDateTime(state.installedAt!)),
      ('Включений', '${state.bootCount}'),
    ];
    return Container(
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _WindowsLogo(size: 28),
              SizedBox(width: 10),
              Text(
                'Windows 11 Pro',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final (k, v) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            k,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            v,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                const Text(
                  'Сборка Hermes OS:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                for (final t in MyPcController.buildTweaks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ',
                            style: TextStyle(fontSize: 12, color: Colors.black54)),
                        Expanded(
                          child: Text(
                            t,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// СВОЙСТВА ФАЙЛА
// =====================================================================

class _PropertiesWindow extends ConsumerWidget {
  final String path;

  const _PropertiesWindow({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(myPcProvider.notifier);
    final f = ctrl.fileAt(path);
    if (f == null) {
      return const Center(
        child: Text('Файл не найден', style: TextStyle(color: Colors.black45)),
      );
    }
    final props = ctrl.propsOf(path);
    return Container(
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                f.isFolder ? Icons.folder : Icons.description_outlined,
                size: 34,
                color: f.isFolder ? const Color(0xFFF2B33D) : Colors.blueGrey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          for (final (k, v) in [
            ('Тип', f.isFolder ? 'Папка' : 'Файл'),
            ('Расположение', f.parent),
            ('Размер', props.size),
            ('Создан', props.createdAt),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      k,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      v,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =====================================================================
// ПАНЕЛЬ ЗАДАЧ
// =====================================================================

class _Taskbar extends StatelessWidget {
  final String theme;
  final bool startMenuOpen;
  final VoidCallback onStart;
  final List<_Win> windows;
  final ValueChanged<_Win> onWindowTap;

  const _Taskbar({
    required this.theme,
    required this.startMenuOpen,
    required this.onStart,
    required this.windows,
    required this.onWindowTap,
  });

  Color get _barColor => switch (theme) {
        'light' => const Color(0xFFE9E9E9),
        'blue' => const Color(0xFF00458A),
        _ => const Color(0xFF1C1C1C),
      };

  Color get _buttonColor => switch (theme) {
        'light' => const Color(0xFFD4D4D4),
        'blue' => const Color(0xFF005DA6),
        _ => const Color(0xFF3A3A3A),
      };

  Color get _textColor => theme == 'light' ? Colors.black87 : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      color: _barColor,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          InkWell(
            onTap: onStart,
            child: Container(
              width: 42,
              height: 36,
              color: startMenuOpen ? _buttonColor : null,
              child: const Center(child: _WindowsLogo(size: 20)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final w in windows)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => onWindowTap(w),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: w.minimized
                                ? _buttonColor.withValues(alpha: 0.6)
                                : _buttonColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Text(
                                w.titleFor(),
                                style: TextStyle(
                                  color: _textColor,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Icon(Icons.wifi, size: 14, color: _textColor.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Icon(Icons.volume_up,
              size: 14, color: _textColor.withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          _Clock(textColor: _textColor),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  final Color textColor;

  const _Clock({this.textColor = Colors.white70});

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Text(
      '${_fmtTime(now)}\n${_fmtDate(now)}',
      textAlign: TextAlign.right,
      style: TextStyle(color: widget.textColor, fontSize: 10, height: 1.3),
    );
  }
}

// =====================================================================
// МЕНЮ ПУСК
// =====================================================================

class _StartMenu extends StatelessWidget {
  final String theme;
  final VoidCallback onClose;
  final void Function(_WinType, String?, String?) onOpen;
  final VoidCallback onShutdown;
  final VoidCallback onReboot;

  const _StartMenu({
    required this.theme,
    required this.onClose,
    required this.onOpen,
    required this.onShutdown,
    required this.onReboot,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = theme == 'light';
    final bg = isLight ? const Color(0xFFF0F0F0) : const Color(0xFF202020);
    final textColor = isLight ? Colors.black87 : Colors.white;
    final iconColor = isLight ? Colors.black54 : Colors.white70;
    final dividerColor = isLight ? const Color(0xFFD0D0D0) : const Color(0xFF3A3A3A);
    return Material(
      color: bg,
      elevation: 8,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StartMenuItem(
              icon: Icons.person,
              label: 'Hermes',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Hermes: система готова. Протокол активен.'),
                  duration: Duration(seconds: 2),
                ),
              ),
            ),
            _StartMenuItem(
              icon: Icons.public,
              label: 'Браузер',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_WinType.browser, null, null),
            ),
            _StartMenuItem(
              icon: Icons.computer,
              label: 'Компьютер',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_WinType.explorer, null, null),
            ),
            _StartMenuItem(
              icon: Icons.terminal,
              label: 'Терминал',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_WinType.terminal, null, null),
            ),
            _StartMenuItem(
              icon: Icons.delete_outline,
              label: 'Корзина',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(
                _WinType.explorer,
                VirtualFsCatalog.recycleBinPath,
                null,
              ),
            ),
            _StartMenuItem(
              icon: Icons.palette_outlined,
              label: 'Персонализация',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_WinType.personalize, null, null),
            ),
            _StartMenuItem(
              icon: Icons.info_outline,
              label: 'Об этом ПК',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_WinType.about, null, null),
            ),
            Divider(color: dividerColor, height: 12),
            _StartMenuItem(
              icon: Icons.restart_alt,
              label: 'Перезагрузка',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () {
                onClose();
                onReboot();
              },
            ),
            _StartMenuItem(
              icon: Icons.power_settings_new,
              label: 'Выключение',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () {
                onClose();
                onShutdown();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StartMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  final VoidCallback onTap;

  const _StartMenuItem({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(color: textColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// ПЕРСОНАЛИЗАЦИЯ
// =====================================================================

class _PersonalizeWindow extends ConsumerStatefulWidget {
  const _PersonalizeWindow();

  @override
  ConsumerState<_PersonalizeWindow> createState() => _PersonalizeWindowState();
}

class _PersonalizeWindowState extends ConsumerState<_PersonalizeWindow> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: ref.read(myPcProvider).state.computerName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myPcProvider).state;
    return Container(
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.all(14),
      child: ListView(
        children: [
          const Text(
            'Обои рабочего стола',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.8,
            children: [
              for (final p in WallpaperPresets.all)
                GestureDetector(
                  onTap: () {
                    ref.read(myPcProvider.notifier).setWallpaper(p.id);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: p.colors,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: state.wallpaperId == p.id
                            ? AppColors.accent
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 28),
          const Text(
            'Имя компьютера',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.black87, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
              hintText: 'HERMES-01',
              isDense: true,
            ),
            onSubmitted: (v) {
              ref.read(myPcProvider.notifier).setComputerName(v.trim());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Имя компьютера обновлено')),
              );
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'А-Z, 0-9, «-» и «_», до 15 символов. Нажмите Enter.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const Divider(height: 28),
          const Text(
            'Тема панели задач',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final t in const [
                (id: 'dark', name: 'Тёмная'),
                (id: 'light', name: 'Светлая'),
                (id: 'blue', name: 'Синяя'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t.name),
                    selected: state.taskbarTheme == t.id,
                    onSelected: (_) {
                      ref
                          .read(myPcProvider.notifier)
                          .setTaskbarTheme(t.id);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// СПЕЦИФИКАЦИИ ИЗ ФЕРМЫ
// =====================================================================

Map<String, String> _specsOf(WidgetRef ref) {
  final farm = ref.read(miningProvider).farm;
  final ids = farm.componentIds;
  const defaults = {
    'CPU': 'Intel Core i5-10400F',
    'GPU': 'NVIDIA GTX 1060',
    'RAM': '8 ГБ DDR4',
    'Storage': 'SSD 512 ГБ NVMe',
  };
  final specs = Map.of(defaults);
  for (final id in ids) {
    final c = ComponentCatalog.byId(id);
    if (c == null) continue;
    switch (c.type) {
      case 'CPU':
        specs['CPU'] = c.name;
        break;
      case 'GPU':
        specs['GPU'] = c.name;
        break;
      case 'RAM':
        specs['RAM'] = c.name;
        break;
      case 'Storage':
        specs['Storage'] = c.name;
        break;
    }
  }
  return specs;
}
