// Вкладка "Мой ПК": виртуальный компьютер с процессом установки Windows.
//
// Экран рисует «монитор»: выключенный ПК, BIOS, установка сборки,
// перезагрузка и рабочий стол с окнами (терминал, проводник, об этом ПК).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/mining_service.dart';
import '../../services/my_pc_service.dart';
import 'browser_window.dart';

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

  @override
  void initState() {
    super.initState();
    // Тик каждую секунду: продвигает BIOS и прогресс установки.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(myPcProvider.notifier).tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
            // Монитор на всю доступную высоту.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: _MonitorFrame(
                  child: switch (phase) {
                    'off' => const _OffScreen(),
                    'bios' => const _BiosScreen(),
                    'setup' => _SetupScreen(state: pc.state),
                    'reboot' => const _RebootScreen(),
                    _ => _DesktopScreen(state: pc.state),
                  },
                ),
              ),
            ),
            // Панель управления.
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
                        'bios' => 'Загрузка BIOS...',
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
                        : ref.read(myPcProvider.notifier).shutdown(),
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
                        : () => ref.read(myPcProvider.notifier).reboot(),
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
// BIOS
// =====================================================================

class _BiosScreen extends StatelessWidget {
  const _BiosScreen();

  static const _lines = [
    'Hermes BIOS v2.5.1 (Build 08/2026)',
    'Copyright (C) 2026 Hermes Systems',
    '',
    'CPU  : Intel Core i5-10400F @ 4.30 GHz',
    'Memory: 8192 MB OK',
    'SATA : SSD 512 GB',
    'Boot : DVD-ROM (Win11_25H2_Hermes_ru-RU.esd)',
    '',
    'Press any key to boot from installation media...',
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            _lines.join('\n'),
            style: const TextStyle(
              color: Color(0xFF33FF66),
              fontFamily: 'monospace',
              fontSize: 15,
              height: 1.6,
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
// РАБОЧИЙ СТОЛ
// =====================================================================

class _DesktopScreen extends ConsumerStatefulWidget {
  final MyPcState state;

  const _DesktopScreen({required this.state});

  @override
  ConsumerState<_DesktopScreen> createState() => _DesktopScreenState();
}

enum _Win {
  terminal,
  explorer,
  about,
  browser,
  personalize,
}

class _DesktopScreenState extends ConsumerState<_DesktopScreen> {
  _Win? _open;
  bool _startMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final wallpaper = WallpaperPresets.colorsFor(widget.state.wallpaperId);
    return Stack(
      children: [
        // Обои.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: wallpaper,
              ),
            ),
          ),
        ),
        // Иконки рабочего стола.
        Positioned(
          left: 10,
          top: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DesktopIcon(
                icon: Icons.public,
                label: 'Браузер',
                onTap: () => _openWindow(_Win.browser),
              ),
              _DesktopIcon(
                icon: Icons.computer,
                label: 'Компьютер',
                onTap: () => _openWindow(_Win.explorer),
              ),
              _DesktopIcon(
                icon: Icons.terminal,
                label: 'Терминал',
                onTap: () => _openWindow(_Win.terminal),
              ),
              _DesktopIcon(
                icon: Icons.palette_outlined,
                label: 'Персонализация',
                onTap: () => _openWindow(_Win.personalize),
              ),
              _DesktopIcon(
                icon: Icons.info_outline,
                label: 'Об этом ПК',
                onTap: () => _openWindow(_Win.about),
              ),
              _DesktopIcon(
                icon: Icons.delete_outline,
                label: 'Корзина',
                onTap: () {
                  ref.read(myPcProvider.notifier).shutdown();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Корзина пуста (система чистая)'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        // Окна.
        if (_open == _Win.terminal)
          _WinWindow(
            title: 'Командная строка — Hermes',
            onClose: () => setState(() => _open = null),
            child: _TerminalWindow(state: widget.state),
          ),
        if (_open == _Win.explorer)
          _WinWindow(
            title: 'Компьютер',
            onClose: () => setState(() => _open = null),
            child: const _ExplorerWindow(),
          ),
        if (_open == _Win.about)
          _WinWindow(
            title: 'Об этом ПК',
            onClose: () => setState(() => _open = null),
            child: _AboutWindow(state: widget.state),
          ),
        if (_open == _Win.browser)
          _WinWindow(
            title: 'Браузер — Hermes',
            onClose: () => setState(() => _open = null),
            child: const BrowserWindow(),
          ),
        if (_open == _Win.personalize)
          _WinWindow(
            title: 'Персонализация',
            onClose: () => setState(() => _open = null),
            child: _PersonalizeWindow(state: widget.state),
          ),
        // Панель задач.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Taskbar(
            theme: widget.state.taskbarTheme,
            startMenuOpen: _startMenuOpen,
            onStart: () => setState(() => _startMenuOpen = !_startMenuOpen),
            openWindows: {
              if (_open != null)
                _open!: _open == _Win.terminal
                    ? 'Терминал'
                    : _open == _Win.explorer
                        ? 'Компьютер'
                        : _open == _Win.about
                            ? 'Об этом ПК'
                            : _open == _Win.browser
                                ? 'Браузер'
                                : 'Персонализация',
            },
            onWindowTap: _open == null
                ? null
                : (w) => setState(() {
                      _startMenuOpen = false;
                      _open = w;
                    }),
          ),
        ),
        // Меню Пуск.
        if (_startMenuOpen)
          Positioned(
            left: 6,
            bottom: 52,
            child: _StartMenu(
              theme: widget.state.taskbarTheme,
              onClose: () => setState(() => _startMenuOpen = false),
              onOpen: _openWindow,
              onShutdown: ref.read(myPcProvider.notifier).shutdown,
              onReboot: ref.read(myPcProvider.notifier).reboot,
            ),
          ),
      ],
    );
  }

  void _openWindow(_Win win) {
    setState(() {
      _startMenuOpen = false;
      _open = win;
    });
  }
}

class _DesktopIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DesktopIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(6),
        width: 84,
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 34, shadows: const [
              Shadow(color: Colors.black54, blurRadius: 4),
            ]),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// ОКНО В СТИЛЕ WINDOWS
// =====================================================================

class _WinWindow extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget child;

  const _WinWindow({
    required this.title,
    required this.onClose,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 58),
          child: Material(
            color: const Color(0xFFF0F0F0),
            elevation: 8,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  height: 30,
                  color: const Color(0xFF2B2B2B),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const _WindowsLogo(size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: onClose,
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// ТЕРМИНАЛ
// =====================================================================

class _TerminalWindow extends ConsumerStatefulWidget {
  final MyPcState state;

  const _TerminalWindow({required this.state});

  @override
  ConsumerState<_TerminalWindow> createState() => _TerminalWindowState();
}

class _TerminalWindowState extends ConsumerState<_TerminalWindow> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<String> _lines = [];
  String _cwd = r'C:\Users\Hermes';

  @override
  void initState() {
    super.initState();
    _lines.add('Hermes OS [Версия 10.0.26100.2000 (Hermes Edition)]');
    _lines.add('(c) Hermes Systems. Все права защищены.');
    _lines.add('');
    _prompt();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _prompt() {
    _lines.add('$_cwd>');
  }

  void _run(String input) {
    final cmd = input.trim();
    if (cmd.isEmpty) return;
    _lines.add(cmd);
    _handle(cmd);
    _prompt();
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _handle(String cmd) {
    final parts = cmd.split(RegExp(r'\s+'));
    final name = parts[0].toLowerCase();

    switch (name) {
      case 'help':
        _lines.addAll([
          'Доступные команды:',
          '  dir              — список файлов',
          '  cd <путь>        — сменить каталог',
          '  type <файл>      — показать содержимое',
          '  echo <текст> > <файл> — создать файл',
          '  del <файл>       — удалить',
          '  ver              — версия ОС',
          '  systeminfo       — характеристики ПК',
          '  shutdown /s      — выключить',
          '  shutdown /r      — перезагрузить',
          '  help             — эта справка',
          '  cls              — очистить экран',
        ]);
        return;
      case 'cls':
        _lines.clear();
        return;
      case 'dir':
        final files = _ls(_cwd);
        if (files.isEmpty) {
          _lines.add('Файлов не найдено.');
          return;
        }
        for (final f in files) {
          if (f.isFolder) {
            _lines.add('   <DIR>   ${f.name}');
          } else {
            _lines.add('           ${f.name}');
          }
        }
        return;
      case 'cd':
        if (parts.length < 2) return;
        final target = _resolve(parts[1]);
        if (target == '') {
          _lines.add('Путь не найден.');
          return;
        }
        _cwd = target;
        return;
      case 'type':
        if (parts.length < 2) return;
        final f = _file(_resolve(parts[1]));
        if (f == null) {
          _lines.add('Файл не найден.');
          return;
        }
        _lines.addAll(f.content.split('\r\n'));
        return;
      case 'echo':
        _handleEcho(cmd);
        return;
      case 'del':
        if (parts.length < 2) return;
        final path = _resolve(parts[1]);
        final f = _file(path);
        if (f == null) {
          _lines.add('Файл не найден.');
          return;
        }
        _fs().deleteFile(f.path);
        _lines.add('Удалено: ${f.path}');
        return;
      case 'ver':
        _lines.add(widget.state.osName);
        _lines.add('Сборка: 26100.2000, 25H2');
        return;
      case 'systeminfo':
        _lines.addAll(_systemInfo());
        return;
      case 'shutdown':
        if (parts.length >= 2 && parts[1] == '/r') {
          _fs().reboot();
        } else {
          _lines.add('Завершение работы...');
          _fs().shutdown();
        }
        return;
      case 'start':
        if (parts.length < 2) return;
        _lines.add('Запуск "${parts[1]}"...');
        return;
      case 'date':
        _lines.add('Текущая дата: ${_fmtDate(DateTime.now())}');
        return;
      case 'time':
        _lines.add('Текущее время: ${_fmtTime(DateTime.now())}');
        return;
      default:
        _lines.add('"$name" не является внутренней или внешней командой.');
        _lines.add('Введите help для списка команд.');
    }
  }

  void _handleEcho(String cmd) {
    final match = RegExp(r'echo\s+(.*?)\s*>\s*(.+)').firstMatch(cmd);
    if (match == null) {
      _lines.add('Использование: echo текст > путь\\файл.txt');
      return;
    }
    final content = match.group(1)!.trim();
    final path = _resolve(match.group(2)!.trim());
    if (!path.toLowerCase().startsWith('c:')) {
      _lines.add('Доступна только запись на C:.');
      return;
    }
    _fs().writeFile(path, content);
    _lines.add('Файл создан: $path');
  }

  List<String> _systemInfo() {
    final specs = _specsOf(ref);
    return [
      'Имя компьютера: ${widget.state.computerName}',
      'ОС: ${widget.state.osName}',
      'Сборка: 26100.2000 (25H2, RU)',
      'Издание: ${widget.state.edition}',
      'Образ: install.esd (${widget.state.imageSizeGb.toStringAsFixed(1)} ГБ, ESD)',
      'Редакций в оригинале: ${widget.state.sourceEditions}',
      'CPU: ${specs['CPU']}',
      'GPU: ${specs['GPU']}',
      'RAM: ${specs['RAM']}',
      'Накопитель: ${specs['Storage']}',
      'Активация: локальная (не требуется)',
    ];
  }

  String _resolve(String p) {
    var path = p;
    if (path == '..') {
      final parent = _cwd.split('\\');
      if (parent.length <= 2) return r'C:\';
      return parent.sublist(0, parent.length - 1).join('\\');
    }
    if (path == '.') return _cwd;
    if (!path.contains('\\')) {
      path = '$_cwd\\$path';
    }
    if (!path.toLowerCase().startsWith('c:')) {
      path = r'C:\' + path;
    }
    // Нормализация.
    final fs = _fs();
    if (_file(path) == null) {
      final children = fs.listDir(_cwd);
      for (final c in children) {
        if (c.name.toLowerCase() == path.split('\\').last.toLowerCase()) {
          return c.path;
        }
      }
      return '';
    }
    return path;
  }

  VirtualFsFile? _file(String path) {
    if (path == '') return null;
    return _fs().fileAt(path);
  }

  List<VirtualFsFile> _ls(String path) => _fs().listDir(path);

  MyPcController _fs() => ref.read(myPcProvider.notifier);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(10),
              child: Text(
                _lines.join('\n'),
                style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Row(
              children: [
                Text(
                  '$_cwd>',
                  style: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (v) {
                      _run(v);
                      _controller.clear();
                    },
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

/// Характеристики ПК из комплектующих майнинг-фермы (или по умолчанию).
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

// =====================================================================
// ПРОВОДНИК
// =====================================================================

class _ExplorerWindow extends ConsumerStatefulWidget {
  const _ExplorerWindow();

  @override
  ConsumerState<_ExplorerWindow> createState() => _ExplorerWindowState();
}

class _ExplorerWindowState extends ConsumerState<_ExplorerWindow> {
  String _path = r'C:\';

  void _openFile(String path) {
    final f = ref.read(myPcProvider.notifier).fileAt(path);
    if (f == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(f.name),
        content: SingleChildScrollView(
          child: Text(
            f.content,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.read(myPcProvider.notifier).listDir(_path);
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: const Color(0xFFE5E5E5),
            child: Row(
              children: [
                IconButton(
                  onPressed: _path != r'C:\'
                      ? () => setState(() {
                            final parts = _path.split('\\');
                            _path = parts.length <= 2
                                ? r'C:\'
                                : parts.sublist(0, parts.length - 1).join('\\');
                          })
                      : null,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _path,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: files.isEmpty
                ? const Center(
                    child: Text(
                      'Папка пуста',
                      style: TextStyle(color: Colors.black45, fontSize: 13),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 90,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final f = files[i];
                      return InkWell(
                        onTap: () {
                          if (f.isFolder) {
                            setState(() => _path = f.path);
                          } else {
                            _openFile(f.path);
                          }
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              f.isFolder
                                  ? Icons.folder
                                  : Icons.description_outlined,
                              color: f.isFolder
                                  ? const Color(0xFFF2B33D)
                                  : Colors.blueGrey,
                              size: 34,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              f.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// ОБ ЭТОМ ПК
// =====================================================================

class _AboutWindow extends ConsumerWidget {
  final MyPcState state;

  const _AboutWindow({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
// ПАНЕЛЬ ЗАДАЧ
// =====================================================================

class _Taskbar extends StatelessWidget {
  final String theme;
  final bool startMenuOpen;
  final VoidCallback onStart;
  final Map<_Win, String> openWindows;
  final ValueChanged<_Win>? onWindowTap;

  const _Taskbar({
    required this.theme,
    required this.startMenuOpen,
    required this.onStart,
    required this.openWindows,
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
          const SizedBox(width: 8),
          for (final entry in openWindows.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => onWindowTap?.call(entry.key),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _buttonColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Text(
                        entry.value,
                        style: TextStyle(color: _textColor, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Spacer(),
          _Clock(textColor: _textColor),
          const SizedBox(width: 8),
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
  final ValueChanged<_Win> onOpen;
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
              onTap: () => onOpen(_Win.browser),
            ),
            _StartMenuItem(
              icon: Icons.computer,
              label: 'Компьютер',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_Win.explorer),
            ),
            _StartMenuItem(
              icon: Icons.terminal,
              label: 'Терминал',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_Win.terminal),
            ),
            _StartMenuItem(
              icon: Icons.palette_outlined,
              label: 'Персонализация',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_Win.personalize),
            ),
            _StartMenuItem(
              icon: Icons.info_outline,
              label: 'Об этом ПК',
              iconColor: iconColor,
              textColor: textColor,
              onTap: () => onOpen(_Win.about),
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
  final MyPcState state;

  const _PersonalizeWindow({required this.state});

  @override
  ConsumerState<_PersonalizeWindow> createState() => _PersonalizeWindowState();
}

class _PersonalizeWindowState extends ConsumerState<_PersonalizeWindow> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.state.computerName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
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
            'Нажмите Enter, чтобы применить',
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
