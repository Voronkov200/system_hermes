// Экран "План" — хаб модулей: Задачи, Поиск, Документы.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('План')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ModuleCard(
            icon: Icons.checklist,
            color: AppColors.accent,
            title: 'Задачи',
            subtitle: 'Список дел от Hermes и Насти, свой план',
            onTap: () => context.go('/plan_tasks'),
          ),
          const SizedBox(height: 12),
          _ModuleCard(
            icon: Icons.travel_explore,
            color: AppColors.cyan,
            title: 'Поиск',
            subtitle: 'Спроси что угодно — ответ с источниками из интернета',
            onTap: () => context.go('/plan_search'),
          ),
          const SizedBox(height: 12),
          _ModuleCard(
            icon: Icons.menu_book,
            color: AppColors.violet,
            title: 'Документы',
            subtitle: 'Учебники, лекции, конспекты по параграфам',
            onTap: () => context.go('/plan_docs'),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
