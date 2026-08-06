// Экран "Жизнь": RPG-механики, адаптированные под реальность.
//
// Слева-сверху: уровень и XP. Показатели (Энергия/Настроение/Дисциплина)
// медленно падают со временем и восстанавливаются действиями.
// Действия дают XP и закрывают квесты; достижения открываются
// по реальным фактам (банк, протокол, счётчики действий).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/life_catalog.dart';
import '../../data/models.dart';
import '../../services/life_service.dart';

class LifeScreen extends ConsumerWidget {
  const LifeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = ref.watch(lifeProvider);
    final s = ex.state;
    final progress = LifeCatalog.levelProgress(s.xp);
    final totalActions = s.actionCounts.values.fold(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: const Text('Жизнь')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Уровень и XP
          _LevelHeader(progress: progress, xp: s.xp),
          const SizedBox(height: 12),
          if (ex.lastEvent != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(ex.lastEvent!,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  ),
                ],
              ),
            ),

          // Показатели
          Row(
            children: [
              _StatCard(
                label: 'Энергия',
                value: s.energy,
                icon: Icons.bolt,
                color: AppColors.warning,
                hint: 'падает без сна и еды',
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Настроение',
                value: s.mood,
                icon: Icons.mood,
                color: AppColors.violet,
                hint: 'падает без отдыха и общения',
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Дисциплина',
                value: s.discipline,
                icon: Icons.gavel,
                color: AppColors.accent,
                hint: 'растёт от действий и протокола',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Текущий квест
          _QuestCard(state: s),
          const SizedBox(height: 16),

          // Статистика
          Row(
            children: [
              _MiniStat(icon: Icons.calendar_today, label: 'День в системе', value: '${s.daysInSystem}'),
              const SizedBox(width: 10),
              _MiniStat(icon: Icons.touch_app, label: 'Действий', value: '$totalActions'),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.emoji_events,
                label: 'Достижения',
                value: '${s.unlockedAchievements.length}/${LifeCatalog.achievements.length}',
              ),
            ],
          ),
          const SizedBox(height: 16),

          const Text('Действия',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Реальные действия восстанавливают показатели и дают XP. '
            'Каждое действие можно выполнять раз в несколько часов.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _ActionGrid(state: s),
          const SizedBox(height: 16),

          const Text('Достижения',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Открываются за реальные факты: выходы из дома, тренировки, '
            'учёбу, деньги на счетах и стабильность протокола.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _AchievementsGrid(state: s),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// =====================================================================
// Компоненты
// =====================================================================

class _LevelHeader extends StatelessWidget {
  final ({int level, int xpInLevel, int xpForNext}) progress;
  final int xp;

  const _LevelHeader({required this.progress, required this.xp});

  @override
  Widget build(BuildContext context) {
    final fraction = progress.xpForNext == 0
        ? 1.0
        : (progress.xpInLevel / progress.xpForNext).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('УРОВЕНЬ',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        color: AppColors.textDim)),
                const Spacer(),
                Text('$xp XP',
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${progress.level}',
                style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent,
                    height: 1.0)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: AppColors.surfaceAlt,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${progress.xpInLevel} / ${progress.xpForNext} XP до уровня ${progress.level + 1}',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final String hint;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final rounded = value.round();
    final isLow = value < 25;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Text('$rounded',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: isLow ? AppColors.danger : color)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (value / 100).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: AppColors.surfaceAlt,
                  color: isLow ? AppColors.danger : color,
                ),
              ),
              const SizedBox(height: 6),
              Text(hint,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestCard extends ConsumerWidget {
  final LifeState state;

  const _QuestCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    const quests = LifeCatalog.quests;
    final isAllDone = s.currentQuestIndex >= quests.length;
    if (isAllDone) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.celebration, color: AppColors.accent),
              SizedBox(width: 12),
              Expanded(
                child: Text('Все квесты выполнены!',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    final q = quests[s.currentQuestIndex];
    return Card(      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('КВЕСТ',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        color: AppColors.textDim)),
                const Spacer(),
                Text('${q.index}/${quests.length}',
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_iconFor(q.icon), color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(q.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(q.description,
                style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.warning, size: 16),
                const SizedBox(width: 4),
                Text('+${q.xp} XP за выполнение',
                    style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MiniStat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.cyan),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends ConsumerWidget {
  final LifeState state;

  const _ActionGrid({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final now = DateTime.now();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in LifeCatalog.actions) ...[
          _ActionButton(action: a, lastUsed: s.lastActionAt[a.id], now: now),
        ],
      ],
    );
  }
}

class _ActionButton extends ConsumerWidget {
  final LifeActionDef action;
  final dynamic lastUsed;
  final DateTime now;

  const _ActionButton({
    required this.action,
    required this.lastUsed,
    required this.now,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCooling = lastUsed != null &&
        now.difference(lastUsed as DateTime) < action.cooldown;
    final remaining = action.cooldown -
        (lastUsed == null ? Duration.zero : now.difference(lastUsed as DateTime));
    final count = ref.watch(lifeProvider).state.actionCounts[action.id] ?? 0;

    return SizedBox(
      width: (MediaQuery.of(context).size.width - 40) / 2,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isCooling
              ? null
              : () async {
                  await ref.read(lifeProvider.notifier).performAction(action.id);
                },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_iconFor(action.icon),
                        size: 18, color: AppColors.accent),
                    const Spacer(),
                    if (count > 0)
                      Text('×$count',
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(action.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(action.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 10)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (isCooling) ...[
                      const Icon(Icons.hourglass_bottom,
                          size: 13, color: AppColors.textDim),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'через ${_fmtCooldown(remaining)}',
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 10),
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.bolt, size: 13, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text('+${action.xp} XP',
                          style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtCooldown(Duration d) {
    if (d.inHours > 0) return '${d.inHours} ч ${d.inMinutes % 60} мин';
    if (d.inMinutes > 0) return '${d.inMinutes} мин';
    return '${d.inSeconds} с';
  }
}

class _AchievementsGrid extends ConsumerWidget {
  final LifeState state;

  const _AchievementsGrid({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final unlocked = s.unlockedAchievements.toSet();
    return Column(
      children: [
        for (final a in LifeCatalog.achievements)
          _AchievementTile(
            achievement: a,
            isUnlocked: unlocked.contains(a.id),
          ),
      ],
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final LifeAchievementDef achievement;
  final bool isUnlocked;

  const _AchievementTile({
    required this.achievement,
    required this.isUnlocked,
  });

  @override
  Widget build(BuildContext context) {
    final color = isUnlocked ? AppColors.accent : AppColors.textDim;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(_iconFor(achievement.icon),
                color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    achievement.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isUnlocked ? AppColors.textPrimary : AppColors.textDim,
                    ),
                  ),
                  Text(achievement.description,
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 11)),
                ],
              ),
            ),
            if (isUnlocked)
              const Icon(Icons.check_circle, color: AppColors.accent, size: 18)
            else
              Icon(Icons.lock, color: AppColors.textDim.withValues(alpha: 0.4), size: 16),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Утилиты
// =====================================================================

IconData _iconFor(String name) {
  switch (name) {
    case 'directions_walk':
      return Icons.directions_walk;
    case 'storefront':
      return Icons.storefront;
    case 'account_balance':
      return Icons.account_balance;
    case 'fitness_center':
      return Icons.fitness_center;
    case 'school':
      return Icons.school;
    case 'work':
      return Icons.work;
    case 'cleaning_services':
      return Icons.cleaning_services;
    case 'self_improvement':
      return Icons.self_improvement;
    case 'menu_book':
      return Icons.menu_book;
    case 'forum':
      return Icons.forum;
    case 'flag':
      return Icons.flag;
    case 'door_front_door':
      return Icons.door_front_door;
    case 'payments':
      return Icons.payments;
    case 'bolt':
      return Icons.bolt;
    case 'local_fire_department':
      return Icons.local_fire_department;
    case 'military_tech':
      return Icons.military_tech;
    case 'calendar_month':
      return Icons.calendar_month;
    case 'calendar_today':
      return Icons.calendar_today;
    case 'verified':
      return Icons.verified;
    case 'savings':
      return Icons.savings;
    case 'currency_exchange':
      return Icons.currency_exchange;
    case 'credit_card':
      return Icons.credit_card;
    default:
      return Icons.flag;
  }
}
