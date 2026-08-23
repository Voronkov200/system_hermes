import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/settings_service.dart';

class WorkScreen extends ConsumerWidget {
  const WorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final hermesOnline = settings.usesDirectLlm || settings.usesHermesServer;
    final providerLabel = settings.usesHermesServer
        ? 'Собственный сервер'
        : settings.usesDirectLlm
            ? settings.hermesLlmModel
            : 'AI не настроен';

    return Scaffold(
      key: const ValueKey('work-screen'),
      appBar: AppBar(
        title: const Text('Работа'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              tooltip: 'Открыть Hermes',
              onPressed: () => context.push('/chat'),
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const _WorkHero(),
          const SizedBox(height: 14),
          _HermesWorkCard(
            online: hermesOnline,
            label: providerLabel,
            onTap: () => context.push('/chat'),
            onSettings: () => context.push('/settings'),
          ),
          const SizedBox(height: 26),
          const _SectionHeading(
            title: 'Делать сейчас',
            subtitle: 'Два главных пространства для движения вперёд',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 176,
            child: Row(
              children: [
                Expanded(
                  child: _MainWorkCard(
                    icon: Icons.school_outlined,
                    color: AppColors.accent,
                    title: 'Учёба',
                    subtitle: '11 класс, учебники и фото решений',
                    badge: 'ЛОКАЛЬНО',
                    onTap: () => context.push('/study'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MainWorkCard(
                    icon: Icons.task_alt_rounded,
                    color: AppColors.cyan,
                    title: 'План',
                    subtitle: 'Задачи, проекты и ближайший результат',
                    badge: 'ФОКУС',
                    onTap: () => context.push('/plan'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const _SectionHeading(
            title: 'Инструменты',
            subtitle: 'Подключай их только когда они нужны задаче',
          ),
          const SizedBox(height: 12),
          _WorkTile(
            icon: Icons.manage_search_rounded,
            color: AppColors.violet,
            title: 'Поиск и исследования',
            subtitle: 'Источники, сравнение и подготовка материала',
            badge: 'WEB',
            onTap: () => context.push('/plan_search'),
          ),
          _WorkTile(
            icon: Icons.description_outlined,
            color: AppColors.warning,
            title: 'Документы',
            subtitle: 'Планы, исследования и сохранённые результаты',
            badge: 'АРХИВ',
            onTap: () => context.push('/plan_docs'),
          ),
          _WorkTile(
            icon: Icons.folder_open_rounded,
            color: AppColors.cyan,
            title: 'Obsidian',
            subtitle: 'Личная база знаний и собственные заметки',
            badge: 'VAULT',
            onTap: () => context.push('/obsidian'),
          ),
        ],
      ),
    );
  }
}

class _WorkHero extends StatelessWidget {
  const _WorkHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3B31), Color(0xFF17283A), Color(0xFF151B27)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.accent.withValues(alpha: .3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MiniPill(text: 'ТРАЕКТОРИЯ', color: AppColors.accent),
          SizedBox(height: 18),
          Text(
            'Учёба → проект →\nпервый собственный доход',
            style: TextStyle(
              fontSize: 23,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -.4,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Сложную цель не нужно держать в голове целиком. Hermes показывает ближайший рабочий участок.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.42),
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _PathStep(number: '01', label: 'Учёба', active: true)),
              SizedBox(width: 7),
              Expanded(child: _PathStep(number: '02', label: 'Проект')),
              SizedBox(width: 7),
              Expanded(child: _PathStep(number: '03', label: 'Доход')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PathStep extends StatelessWidget {
  final String number;
  final String label;
  final bool active;

  const _PathStep({required this.number, required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? .12 : .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: active ? .22 : .1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(number, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _HermesWorkCard extends StatelessWidget {
  final bool online;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onSettings;

  const _HermesWorkCard({
    required this.online,
    required this.label,
    required this.onTap,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.accent : AppColors.warning;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: .24), color.withValues(alpha: .08)],
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Hermes Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 7),
                        _MiniPill(text: online ? 'ГОТОВ' : 'ОФЛАЙН', color: color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Настроить API',
                onPressed: onSettings,
                icon: const Icon(Icons.tune_rounded, size: 20),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainWorkCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  const _MainWorkCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconBadge(icon: icon, color: color),
                  const Spacer(),
                  _MiniPill(text: badge, color: color),
                ],
              ),
              const Spacer(),
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Text('Открыть', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: color, size: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _WorkTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  const _WorkTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _IconBadge(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
                        _MiniPill(text: badge, color: color),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .55,
        ),
      ),
    );
  }
}
