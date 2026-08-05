// Экран "PC Builder": выбор комплектующих + установка ОС и драйверов
// через симуляцию терминала.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/mining_service.dart';

class PcBuilderScreen extends ConsumerStatefulWidget {
  const PcBuilderScreen({super.key});

  @override
  ConsumerState<PcBuilderScreen> createState() => _PcBuilderScreenState();
}

class _PcBuilderScreenState extends ConsumerState<PcBuilderScreen> {
  final Set<String> _selected = {};
  bool _showOs = false;

  static const _osSteps = [
    'HERMES-OS LOADER v3.1',
    '> Чтение комплектующих…',
    '> Инициализация CPU… OK',
    '> Инициализация RAM… OK',
    '> Монтирование дисков… OK',
    '> Установка ядра…',
    '> Установка базовых модулей…',
    '> Создание пользователя "tim"…',
    '> СИСТЕМА ГОТОВА',
  ];

  static const _driverSteps = [
    'Установка драйверов GPU…  [####......]',
    'Установка драйверов GPU…  [########..]',
    'Установка драйверов GPU…  [##########]',
    'Драйверы сети… OK',
    'Оптимизация майнинга… OK',
    '> ФЕРМА ЗАПУЩЕНА. ХЕШРЕЙТ НОМИНАЛЬНЫЙ.',
  ];

  void _toggleComponent(String id) {
    final c = ComponentCatalog.byId(id)!;
    setState(() {
      // одна комплектующая на тип
      _selected.removeWhere((x) => ComponentCatalog.byId(x)!.type == c.type);
      _selected.add(id);
    });
  }

  double get _totalPower {
    double sum = 0;
    for (final id in _selected) {
      sum += ComponentCatalog.byId(id)!.power;
    }
    return sum;
  }

  Future<void> _runInstall(List<String> steps, Future<void> Function() onDone) async {
    final lines = <String>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (_) => TerminalSim(lines: lines, steps: steps),
    );
    await onDone();
  }

  @override
  Widget build(BuildContext context) {
    final mining = ref.watch(miningProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('PC Builder'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('ВЫБЕРИ КОМПЛЕКТУЮЩИЕ',
              style: TextStyle(fontSize: 12, letterSpacing: 1, color: AppColors.textDim)),
          const SizedBox(height: 8),
          for (final type in const ['CPU', 'GPU', 'RAM', 'Storage']) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(type,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.cyan)),
            ),
            ...ComponentCatalog.all.where((c) => c.type == type).map((c) {
              final isSelected = _selected.contains(c.id);
              return Card(
                color: isSelected ? const Color(0xFF0D2B22) : AppColors.surface,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _toggleComponent(c.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected ? AppColors.accent : AppColors.textDim,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(c.name, style: const TextStyle(fontSize: 13)),
                        ),
                        Text('+${fmt0(c.power)} MH',
                            style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? AppColors.accent : AppColors.textDim)),
                        const SizedBox(width: 8),
                        Text('${c.price} оч',
                            style: const TextStyle(fontSize: 11, color: AppColors.warning)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2836)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.warning),
                const SizedBox(width: 10),
                Text('Мощность сборки: ${fmt0(_totalPower)} MH',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _selected.length < 4
                ? null
                : () async {
                    await ref
                        .read(miningProvider.notifier)
                        .startBuild(_selected.toList());
                    setState(() => _showOs = true);
                  },
            icon: const Icon(Icons.build_circle_outlined),
            label: Text(_selected.length < 4
                ? 'Выбери по 1 комплектующей на тип (${_selected.length}/4)'
                : 'Начать сборку'),
          ),

          if (_showOs) ...[
            const SizedBox(height: 20),
            const Text('УСТАНОВКА',
                style: TextStyle(fontSize: 12, letterSpacing: 1, color: AppColors.textDim)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.language, size: 18, color: AppColors.cyan),
                        const SizedBox(width: 8),
                        const Text('Операционная система',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton(
                          onPressed: mining.farm.osInstalled == 'none'
                              ? () => _runInstall(
                                  _osSteps,
                                  () => ref
                                      .read(miningProvider.notifier)
                                      .installOs('HERMES-OS v1.0'),
                                )
                              : null,
                          child: Text(mining.farm.osInstalled == 'none'
                              ? 'Установить'
                              : mining.farm.osInstalled),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Row(
                      children: [
                        const Icon(Icons.hardware, size: 18, color: AppColors.cyan),
                        const SizedBox(width: 8),
                        const Text('Драйверы',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton(
                          onPressed:
                              (mining.farm.osInstalled == 'none' ||
                                      mining.farm.driversInstalled)
                                  ? null
                                  : () => _runInstall(
                                      _driverSteps,
                                      () => ref
                                          .read(miningProvider.notifier)
                                          .installDrivers(),
                                    ),
                          child: Text(mining.farm.driversInstalled
                              ? 'Установлены ✓'
                              : 'Установить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (mining.farm.status == 'online') ...[
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppColors.accent),
                ),
                child: const Text('ФЕРМА РАБОТАЕТ',
                    style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Симуляция терминала: построчный вывод установки.
class TerminalSim extends StatefulWidget {
  final List<String> lines;
  final List<String> steps;

  const TerminalSim({super.key, required this.lines, required this.steps});

  @override
  State<TerminalSim> createState() => _TerminalSimState();
}

class _TerminalSimState extends State<TerminalSim> {
  final ScrollController _scroll = ScrollController();
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    for (var i = 0; i < widget.steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() => _shown = i + 1);
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.steps.take(_shown).toList();
    return Container(
      height: 320,
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('HERMES TERMINAL',
                style: TextStyle(
                    color: AppColors.accent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    letterSpacing: 2)),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: visible.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  visible[i],
                  style: const TextStyle(
                    color: Color(0xFF7CF5C8),
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('_', style: TextStyle(color: AppColors.accent, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
