// Маршрутизация приложения (go_router).

import 'package:go_router/go_router.dart';

import 'features/bank/bank_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/habits/habits_screen.dart';
import 'features/home/home_screen.dart';
import 'features/mining/mining_screen.dart';
import 'features/mining/pc_builder_screen.dart';
import 'features/obsidian/note_screen.dart';
import 'features/obsidian/obsidian_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // Основные вкладки (нижняя навигация).
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/bank', builder: (context, state) => const BankScreen()),
        GoRoute(path: '/mining', builder: (context, state) => const MiningScreen()),
        GoRoute(path: '/habits', builder: (context, state) => const HabitsScreen()),
        GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),
      ],
    ),
    // Полноэкранные экраны.
    GoRoute(path: '/pc_builder', builder: (context, state) => const PcBuilderScreen()),
    GoRoute(path: '/obsidian', builder: (context, state) => const ObsidianScreen()),
    GoRoute(
      path: '/note',
      builder: (context, state) => NoteScreen(notePath: state.extra as String),
    ),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
  ],
);
