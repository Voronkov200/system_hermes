// Экран "Майнинг-ферма": статус, хешрейт, очки, множители.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/mining_service.dart';

class MiningScreen extends ConsumerStatefulWidget {
  const MiningScreen({super.key});

  @override
  ConsumerState<MiningScreen> createState() => _MiningScreenState();
}

class _MiningScreenState extends ConsumerState<MiningScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Периодическое начисление очков, пока экран открыт.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(miningProvider);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mining = ref.watch(miningProvider);
    final farm = mining.farm;

    final (statusText, statusColor) = switch (farm.status) {
      'online' => ('ОНЛАЙН', AppColors.accent),
      'building' => ('СБОРКА…', AppColors.warning),
      'locked' => (
          'ERROR — блокировка ${farm.lockUntil == null ? '' : 'до ${fmtTime(farm.lockUntil!)}'}',
          AppColors.danger
        ),
      _ => ('ОФФЛАЙН', AppColors.textDim),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Майнинг-ферма'),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_outlined),
            tooltip: 'PC Builder',
            onPressed: () => context.push('/pc_builder'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Статус фермы
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: statusColor),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.memory, color: statusColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  mining.locked ? '0' : fmt0(mining.hashRate),
                  style: const TextStyle(
                      fontSize: 44, fontWeight: FontWeight.w800, color: AppColors.accent),
                ),
                const Text('MH/s',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Очки и доход
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'ОЧКИ ПРОГРЕССА',
                  value: fmt0(farm.points),
                  icon: Icons.stars,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'ДОХОД',
                  value: '${fmt2(mining.pointsPerHour)}/ч',
                  icon: Icons.trending_up,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Комплектующие
          if (farm.componentIds.isNotEmpty) ...[
            const Text('КОМПЛЕКТУЮЩИЕ',
                style: TextStyle(fontSize: 12, letterSpacing: 1, color: AppColors.textDim)),
            const SizedBox(height: 8),
            ...farm.componentIds.map((id) {
              final c = ComponentCatalog.byId(id);
              if (c == null) return const SizedBox.shrink();
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings, size: 18, color: AppColors.cyan),
                title: Text('${c.name} (${c.type})', style: const TextStyle(fontSize: 13)),
                trailing: Text('+${fmt0(c.power)} MH',
                    style: const TextStyle(color: AppColors.accent, fontSize: 12)),
              );
            }),
            const SizedBox(height: 8),
            Text('ОС: ${farm.osInstalled == 'none' ? 'не установлена' : farm.osInstalled}'
                ' • Драйверы: ${farm.driversInstalled ? '✓' : '✗'}',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],

          // Множители от Протокола
          if (mining.multipliers.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('МНОЖИТЕЛИ ПРОТОКОЛА',
                style: TextStyle(fontSize: 12, letterSpacing: 1, color: AppColors.textDim)),
            const SizedBox(height: 8),
            ...mining.multipliers.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(m, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('Итого множитель: ×${mining.multiplier.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
          ],

          if (farm.status == 'offline') ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.push('/pc_builder'),
              icon: const Icon(Icons.build),
              label: const Text('Собрать ферму'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.cyan),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(fontSize: 10, color: AppColors.textDim, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}
