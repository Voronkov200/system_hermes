// Маршрутизация приложения (go_router).

import 'package:go_router/go_router.dart';

import 'features/bank/bank_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/habits/habits_screen.dart';
import 'features/home/home_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/life/life_screen.dart';
import 'features/mining/mining_screen.dart';
import 'features/mining/pc_builder_screen.dart';
import 'features/obsidian/note_screen.dart';
import 'features/obsidian/obsidian_screen.dart';
import 'features/plan/docs_screen.dart';
import 'features/plan/plan_screen.dart';
import 'features/plan/record_screen.dart';
import 'features/plan/search_screen.dart';
import 'features/plan/tasks_screen.dart';
import 'features/plan/web_view_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell.dart';
import 'features/study/paragraph_screen.dart';
import 'features/study/study_screen.dart';
import 'features/study/subject_screen.dart';
import 'services/study/study_service.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // Основные вкладки (нижняя навигация).
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/bank', builder: (context, state) => const BankScreen()),
        GoRoute(path: '/life', builder: (context, state) => const LifeScreen()),
        GoRoute(path: '/mining', builder: (context, state) => const MiningScreen()),
        GoRoute(path: '/habits', builder: (context, state) => const HabitsScreen()),
        GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),
        GoRoute(path: '/plan', builder: (context, state) => const PlanScreen()),
        GoRoute(path: '/study', builder: (context, state) => const StudyScreen()),
      ],
    ),
    // Полноэкранные экраны.
    GoRoute(path: '/pc_builder', builder: (context, state) => const PcBuilderScreen()),
    GoRoute(
      path: '/study_subject/:id',
      builder: (context, state) => SubjectScreen(
        subjectId: state.pathParameters['id'] ?? '',
        initial: state.extra as StudySubject?,
      ),
    ),
    GoRoute(
      path: '/study_paragraph/:id',
      builder: (context, state) => ParagraphScreen(
        paragraphId: state.pathParameters['id'] ?? '',
        initial: state.extra as StudyParagraph?,
      ),
    ),
    GoRoute(path: '/plan_tasks', builder: (context, state) => const TasksScreen()),
    GoRoute(path: '/plan_search', builder: (context, state) => const SearchScreen()),
    GoRoute(path: '/plan_docs', builder: (context, state) => const DocsScreen()),
    GoRoute(path: '/plan_record', builder: (context, state) => const RecordScreen()),
    GoRoute(
      path: '/web',
      builder: (context, state) =>
          WebViewScreen(url: state.extra as String? ?? 'https://example.com'),
    ),
    GoRoute(path: '/obsidian', builder: (context, state) => const ObsidianScreen()),
    GoRoute(path: '/journal', builder: (context, state) => const JournalScreen()),
    GoRoute(
      path: '/note',
      builder: (context, state) =>
          NoteScreen(notePath: state.extra as String? ?? ''),
    ),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
  ],
);
