import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('more-screen'),
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Жизнь и система',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _MoreTile(
            icon: Icons.self_improvement,
            color: AppColors.accent,
            title: 'Жизнь',
            subtitle: 'Самостоятельные действия, XP и достижения',
            onTap: () => context.push('/life'),
          ),
          _MoreTile(
            icon: Icons.fitness_center,
            color: AppColors.cyan,
            title: 'Протокол',
            subtitle: 'Тренировки и ежедневная стабильность',
            onTap: () => context.push('/habits'),
          ),
          const SizedBox(height: 14),
          const Text(
            'Данные и настройки',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _MoreTile(
            icon: Icons.history,
            color: AppColors.violet,
            title: 'Журнал изменений',
            subtitle: 'История действий и важных записей',
            onTap: () => context.push('/journal'),
          ),
          _MoreTile(
            icon: Icons.settings_outlined,
            color: AppColors.textDim,
            title: 'Настройки',
            subtitle: 'Пенсия, тема, агент, Vault и резервное управление',
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreTile({
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
