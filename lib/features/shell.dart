// Каркас приложения: нижняя навигация по модулям.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _indexFor(String path) {
    if (path.startsWith('/bank')) return 1;
    if (path.startsWith('/life')) return 2;
    if (path.startsWith('/mining')) return 3;
    if (path.startsWith('/habits')) return 4;
    if (path.startsWith('/chat')) return 5;
    if (path.startsWith('/plan')) return 6;
    if (path.startsWith('/study')) return 7;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _indexFor(GoRouterState.of(context).uri.path);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          const paths = [
            '/', '/bank', '/life', '/mining', '/habits', '/chat', '/plan', '/study',
          ];
          context.go(paths[i]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Банк',
          ),
          NavigationDestination(
            icon: Icon(Icons.self_improvement_outlined),
            selectedIcon: Icon(Icons.self_improvement),
            label: 'Жизнь',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            selectedIcon: Icon(Icons.memory),
            label: 'Майнинг',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Протокол',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Hermes',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rtl),
            selectedIcon: Icon(Icons.checklist),
            label: 'План',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Учёба',
          ),
        ],
      ),
    );
  }
}
