// Каркас приложения: четыре понятные области вместо списка модулей.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

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
    final theme = Theme.of(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? AppColors.surfaceRaised
                : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? AppColors.border
                  : const Color(0xFFDCE4EA),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .22),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: NavigationBar(
              key: const ValueKey('main-navigation'),
              selectedIndex: index,
              onDestinationSelected: (i) {
                const paths = ['/', '/work', '/money', '/more'];
                context.go(paths[i]);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard_rounded),
                  label: 'Главная',
                ),
                NavigationDestination(
                  icon: Icon(Icons.rocket_launch_outlined),
                  selectedIcon: Icon(Icons.rocket_launch_rounded),
                  label: 'Работа',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: 'Деньги',
                ),
                NavigationDestination(
                  icon: Icon(Icons.widgets_outlined),
                  selectedIcon: Icon(Icons.widgets_rounded),
                  label: 'Ещё',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
