// Экран «Аналитика»: показывает готовые ИИ-отчёты (ТГК-аналитика + психпортрет),
// подтянутые из GitHub-каталога data/analytics/. Pull-to-refresh для обновления.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/analytics_service.dart';
import 'analytics_report.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    ref.invalidate(analyticsReportsProvider);
    await ref.read(analyticsReportsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsReportsProvider);

    return Scaffold(
      key: const ValueKey('analytics-screen'),
      appBar: AppBar(
        title: const Text('Аналитика'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: 'Не удалось загрузить отчёты: $err',
          onRetry: () => ref.invalidate(analyticsReportsProvider),
        ),
        data: (data) => _AnalyticsBody(
          data: data,
          onRefresh: () => _refresh(context, ref),
          onRetry: () => ref.invalidate(analyticsReportsProvider),
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final AnalyticsData data;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  const _AnalyticsBody({
    required this.data,
    required this.onRefresh,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tgk = data.tgk;
    final psych = data.psych;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const _IntroCard(),
          const SizedBox(height: 6),
          if (data.error != null)
            _ErrorBanner(message: data.error!, onRetry: onRetry),
          if (tgk == null && psych == null)
            _ErrorView(
              message: 'Нет отчётов. Проверь синк и попробуй обновить.',
              onRetry: onRetry,
            )
          else ...[
            if (tgk != null)
              _ModuleCard(
                report: tgk,
                color: AppColors.accent,
                icon: Icons.chat_bubble_outline_rounded,
              ),
            if (psych != null)
              _ModuleCard(
                report: psych,
                color: AppColors.violet,
                icon: Icons.person_outline_rounded,
              ),
          ],
          const SizedBox(height: 8),
          Text(
            'Отчёты считает ИИ на ПК по данным D:\\тг и D:\\акк 1, публикуются в '
            'GitHub и обновляются по расписанию.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF25223B), Color(0xFF172537), Color(0xFF141A24)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.violet.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(Icons.insights_rounded, color: AppColors.accent),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Аналитика о тебе',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  'ТГК за ~1.5 года · психпортрет TikTok',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final AnalyticsReport report;
  final Color color;
  final IconData icon;

  const _ModuleCard({
    required this.report,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final chips = _summaryChips(report);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: color,
        collapsedIconColor: AppColors.textDim,
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          report.title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            report.subtitle,
            style: const TextStyle(fontSize: 12, height: 1.35),
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in chips) Chip(label: Text(c)),
              ],
            ),
          ),
          if (report.generatedAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Сгенерировано: ${report.generatedAt}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                ),
              ),
            ),
          if (report.source.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Источник: ${report.source}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 430),
              child: report.bodyText.isEmpty
                  ? const Text('Отчёт пуст.')
                  : SingleChildScrollView(
                      child: SelectableText(
                        report.bodyText,
                        style: const TextStyle(fontSize: 13.5, height: 1.5),
                        textAlign: TextAlign.start,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Чипы из структурированных данных отчёта.
  List<String> _summaryChips(AnalyticsReport report) {
    if (report.kind == 'tgk') {
      final weights = report.structuredMap('theme_weights');
      final top = weights.entries.toList()
        ..sort((a, b) => _num(b.value).compareTo(_num(a.value)));
      return top.take(6).map((e) => '${e.key} ${(_num(e.value) * 100).round()}%').toList();
    }
    // psych
    final interests = report.structuredList('interests');
    final traits = report.structuredList('personality_traits');
    return [
      ...interests.take(5),
      ...traits.take(4),
    ];
  }

  double _num(dynamic v) => v is num ? v.toDouble() : 0;
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textDim),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.danger.withValues(alpha: .08),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
        title: const Text('Часть отчётов не загружена'),
        subtitle: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: TextButton(onPressed: onRetry, child: const Text('Повторить')),
      ),
    );
  }
}
