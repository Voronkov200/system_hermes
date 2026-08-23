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
    return Scaffold(
      key: const ValueKey('work-screen'),
      appBar: AppBar(title: const Text('Работа')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accent.withValues(alpha: .2),
                  AppColors.cyan.withValues(alpha: .06),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border:
                  Border.all(color: AppColors.accent.withValues(alpha: .34)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.trending_up, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Путь к самостоятельности',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Учёба → проекты → фриланс → собственный доход. '
                        'Здесь собраны инструменты, которые двигают этот путь.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _HermesWorkCard(
            online: hermesOnline,
            label: settings.usesHermesServer
                ? 'собственный сервер'
                : settings.usesDirectLlm
                    ? settings.hermesLlmModel
                    : 'офлайн-режим',
            onTap: () => context.push('/chat'),
            onSettings: () => context.push('/settings'),
          ),
          const SizedBox(height: 16),
          const _WorkSectionTitle('Следующий шаг'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MainWorkCard(
                  icon: Icons.school_outlined,
                  color: AppColors.accent,
                  title: 'Учёба',
                  subtitle: 'Учебники и фото ГДЗ',
                  onTap: () => context.push('/study'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MainWorkCard(
                  icon: Icons.checklist_rtl,
                  color: AppColors.cyan,
                  title: 'План',
                  subtitle: 'Задачи и проекты',
                  onTap: () => context.push('/plan'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _WorkSectionTitle('Инструменты'),
          const SizedBox(height: 10),
          _WorkTile(
            icon: Icons.search,
            color: AppColors.violet,
            title: 'Поиск и исследования',
            subtitle: 'Собрать источники и подготовить материал',
            onTap: () => context.push('/plan_search'),
          ),
          _WorkTile(
            icon: Icons.description_outlined,
            color: AppColors.violet,
            title: 'Документы',
            subtitle: 'Сохранённые планы, исследования и результаты',
            onTap: () => context.push('/plan_docs'),
          ),
          _WorkTile(
            icon: Icons.folder_open_outlined,
            color: AppColors.cyan,
            title: 'Obsidian',
            subtitle: 'Личная база знаний и заметки',
            onTap: () => context.push('/obsidian'),
          ),
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
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.auto_awesome, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hermes Agent',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      online ? 'Подключён · $label' : 'Без AI · $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Настроить API',
                onPressed: onSettings,
                icon: const Icon(Icons.tune),
              ),
              const Icon(Icons.chevron_right),
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
  final VoidCallback onTap;

  const _MainWorkCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );
}

class _WorkSectionTitle extends StatelessWidget {
  final String text;

  const _WorkSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
    );
  }
}

class _WorkTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WorkTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        minVerticalPadding: 14,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .13),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
