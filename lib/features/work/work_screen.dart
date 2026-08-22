import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

class WorkScreen extends StatelessWidget {
  const WorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Работа')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.accent.withValues(alpha: .34)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.trending_up, color: AppColors.accent),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
          _WorkTile(
            icon: Icons.school_outlined,
            color: AppColors.accent,
            title: 'Учёба',
            subtitle:
                'Все учебники и локальный разбор параграфов без интернета',
            onTap: () => context.go('/study'),
          ),
          _WorkTile(
            icon: Icons.checklist_rtl,
            color: AppColors.cyan,
            title: 'План и задачи',
            subtitle: 'Следующие действия, проекты и этапы фриланса',
            onTap: () => context.go('/plan'),
          ),
          _WorkTile(
            icon: Icons.chat_bubble_outline,
            color: AppColors.warning,
            title: 'Hermes Agent',
            subtitle: 'Помощь, готовые примеры и разбор сложных шагов',
            onTap: () => context.go('/chat'),
          ),
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
