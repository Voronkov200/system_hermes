// Главный экран: сводка по всем модулям системы.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/bank_service.dart';
import '../../services/habits_service.dart';
import '../../services/mining_service.dart';
import '../../services/nbrb_api.dart';
import '../../services/obsidian_service.dart';
import '../../services/settings_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bank = ref.watch(bankProvider);
    final mining = ref.watch(miningProvider);
    final habits = ref.watch(habitsProvider);
    final obsidian = ref.watch(obsidianProvider);
    final settings = ref.watch(settingsProvider);
    final ratesAsync = ref.watch(ratesProvider);
    final rates = ratesAsync.valueOrNull;

    final totalByn = bank.totalByn(rates: rates, assetsCurrency: settings.assetsCurrency);
    final clean = habits.cleanStreak();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: AppColors.accent),
            SizedBox(width: 8),
            Text('SYSTEM: HERMES'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusBanner(mining: mining, clean: clean),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              _ModuleCard(
                title: 'Центральный Банк',
                subtitle: '${fmt2(totalByn)} BYN',
                icon: Icons.account_balance_wallet,
                color: AppColors.accent,
                onTap: () => context.go('/bank'),
              ),
              _ModuleCard(
                title: 'Майнинг-ферма',
                subtitle: mining.locked
                    ? 'ЗАБЛОКИРОВАНА'
                    : mining.farm.status == 'online'
                        ? '${fmt0(mining.hashRate)} MH/s'
                        : 'Собери ПК',
                icon: Icons.memory,
                color: AppColors.cyan,
                onTap: () => context.go('/mining'),
              ),
              _ModuleCard(
                title: 'Протокол',
                subtitle: '$clean дней чистоты',
                icon: Icons.fitness_center,
                color: AppColors.danger,
                onTap: () => context.go('/habits'),
              ),
              _ModuleCard(
                title: 'Obsidian',
                subtitle: obsidian.vaultPath == null
                    ? 'Vault не выбран'
                    : '${obsidian.notes.length} заметок',
                icon: Icons.description_outlined,
                color: AppColors.violet,
                onTap: () => context.push('/obsidian'),
              ),
              _ModuleCard(
                title: 'Hermes Agent',
                subtitle: 'Чат-контроллер',
                icon: Icons.chat_bubble_outline,
                color: AppColors.warning,
                onTap: () => context.go('/chat'),
              ),
              _ModuleCard(
                title: 'Настройки',
                subtitle: 'Тема, пенсия, Vault',
                icon: Icons.settings_outlined,
                color: AppColors.textDim,
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (rates != null && rates.isNotEmpty) _RatesCard(rates: rates),
          const SizedBox(height: 16),
          _HabitStrip(habits: habits),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final MiningState mining;
  final int clean;

  const _StatusBanner({required this.mining, required this.clean});

  @override
  Widget build(BuildContext context) {
    final String status;
    final Color color;
    if (mining.locked) {
      status = 'СИСТЕМА В РЕЖИМЕ ОШИБКИ — ферма заблокирована';
      color = AppColors.danger;
    } else if (mining.farm.status == 'online') {
      status = 'СИСТЕМА ОНЛАЙН — дисциплина активна';
      color = AppColors.accent;
    } else {
      status = 'СИСТЕМА ИНИЦИАЛИЗИРУЕТСЯ — собери ферму';
      color = AppColors.warning;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text('$clean дн',
              style: const TextStyle(
                  color: AppColors.warning, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatesCard extends StatelessWidget {
  final List<CurrencyRate> rates;

  const _RatesCard({required this.rates});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Курсы Нацбанка РБ',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: rates.map((r) {
                return Expanded(
                  child: Column(
                    children: [
                      Text(r.code,
                          style: const TextStyle(color: AppColors.textDim)),
                      Text('${r.perUnit.toStringAsFixed(2)} BYN',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitStrip extends StatelessWidget {
  final HabitsState habits;

  const _HabitStrip({required this.habits});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final h in habits.habits) {
      final done = h.type == 'bad'
          ? h.currentStreak > 0
          : h.doneToday();
      items.add(Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done ? AppColors.accent : const Color(0xFF1E2836)),
        ),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? AppColors.accent : AppColors.textDim,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(h.name)),
            Text(h.type == 'bad' ? '${h.currentStreak} дн' : 'стрик ${h.currentStreak}',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
      ));
    }
    return Column(children: items);
  }
}
