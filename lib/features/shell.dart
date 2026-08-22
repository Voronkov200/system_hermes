// Каркас приложения: четыре понятные области вместо списка модулей.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _indexFor(String path) {
    if (path.startsWith('/work') ||
        path.startsWith('/plan') ||
        path.startsWith('/study') ||
        path.startsWith('/chat')) {
      return 1;
    }
    if (path.startsWith('/money') || path.startsWith('/bank')) return 2;
    if (path.startsWith('/more') ||
        path.startsWith('/life') ||
        path.startsWith('/habits') ||
        path.startsWith('/obsidian') ||
        path.startsWith('/journal') ||
        path.startsWith('/settings')) {
      return 3;
    }
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
          const paths = ['/', '/work', '/money', '/more'];
          context.go(paths[i]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Работа',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Деньги',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.apps),
            label: 'Ещё',
          ),
        ],
      ),
    );
  }
}
