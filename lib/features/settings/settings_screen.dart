// Экран настроек: тема, пенсия, Vault, Hermes Agent, GitHub, сброс.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/bank_service.dart';
import '../../services/habits_service.dart';
import '../../services/hermes_service.dart';
import '../../services/journal_service.dart';
import '../../services/llm_connection_service.dart';
import '../../services/obsidian_service.dart';
import '../../services/settings_service.dart';
import '../../services/tasks_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _resetAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Сбросить все данные?'),
        content: const Text(
            'Будут удалены: локальные счета, карты, транзакции, привычки и '
            'история чата. '
            'Это действие необратимо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(bankProvider.notifier).reset();
    await ref.read(habitsProvider.notifier).reset();
    await ref.read(chatProvider.notifier).reset();
    await ref.read(tasksProvider.notifier).reset();
    await ref.read(journalProvider.notifier).clear();
    if (context.mounted) {
      toast(context, 'Все данные сброшены');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _SettingsIntro(
            darkMode: s.themeMode == ThemeMode.dark,
            aiReady: s.usesDirectLlm || s.usesHermesServer,
            pension: s.pensionAmount,
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Внешний вид'),
          SwitchListTile(
            title: const Text('Тёмная тема'),
            subtitle: const Text('Киберпанк-стиль по умолчанию'),
            value: s.themeMode == ThemeMode.dark,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
          const Divider(),

          const _SectionTitle('Деньги'),
          ListTile(
            title: const Text('День получения пенсии'),
            subtitle: Text('${s.pensionDay}-е число каждого месяца'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final day = await showDialog<int>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  backgroundColor: AppColors.surface,
                  title: const Text('День пенсии'),
                  children: List.generate(28, (i) {
                    final d = i + 1;
                    return SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, d),
                      child: Text('$d-е число'),
                    );
                  }),
                ),
              );
              if (day != null) {
                await ref.read(settingsProvider.notifier).setPensionDay(day);
              }
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.verified_outlined,
              color: AppColors.accent,
            ),
            title: const Text('Официальная пенсия'),
            subtitle: Text('${fmt2(s.pensionAmount)} BYN в месяц'),
            trailing: const Text(
              '390 BYN',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Divider(),

          const _SectionTitle('Obsidian Vault'),
          ListTile(
            title: const Text('Папка Vault'),
            subtitle: Text(s.vaultPath.isEmpty ? 'не выбрана' : s.vaultPath,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: FilledButton.tonal(
              onPressed: () async {
                await ref.read(obsidianProvider.notifier).pickVault();
                if (context.mounted) toast(context, 'Vault обновлён');
              },
              child: const Text('Выбрать'),
            ),
          ),
          const Divider(),

          const _SectionTitle('Hermes AI'),
          const _HermesConnectionCard(),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.tune, color: AppColors.violet),
              title: const Text(
                'Дополнительные настройки AI',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Другая модель, свой сервер и голос',
                style: TextStyle(fontSize: 11),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ProviderPreset(
                        label: 'B.ai Flash',
                        url: 'https://api.b.ai/v1',
                        model: 'deepseek-v4-flash',
                      ),
                      _ProviderPreset(
                        label: 'Vision (эксп.)',
                        url: 'https://api.b.ai/v1',
                        model: 'deepseek-v4-flash-vision-exp',
                      ),
                    ],
                  ),
                ),
                _TextFieldSetting(
                  label: 'Base URL модели',
                  initial: s.hermesLlmUrl,
                  hint: AppConstants.hermesLlmDefaultUrl,
                  onSave: (v) => ref
                      .read(settingsProvider.notifier)
                      .setHermesLlmUrl(v),
                ),
                _TextFieldSetting(
                  label: 'Название модели',
                  initial: s.hermesLlmModel,
                  hint: AppConstants.hermesLlmDefaultModel,
                  onSave: (v) => ref
                      .read(settingsProvider.notifier)
                      .setHermesLlmModel(v),
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  secondary: const Icon(Icons.dns_outlined),
                  title: const Text('Собственный сервер Hermes'),
                  subtitle: Text(
                    s.hermesMode == HermesModes.server
                        ? 'Активен вместо B.ai'
                        : 'Выключен — используется прямая модель',
                  ),
                  value: s.hermesMode == HermesModes.server,
                  onChanged: (enabled) => ref
                      .read(settingsProvider.notifier)
                      .setHermesMode(
                        enabled ? HermesModes.server : HermesModes.direct,
                      ),
                ),
                _TextFieldSetting(
                  label: 'URL собственного сервера',
                  initial: s.hermesUrl,
                  hint: 'https://your-server.example/api/hermes',
                  onSave: (v) =>
                      ref.read(settingsProvider.notifier).setHermesUrl(v),
                ),
                _TextFieldSetting(
                  label: 'Ключ собственного сервера',
                  initial: s.hermesApiKey,
                  hint: 'необязательно',
                  obscure: true,
                  onSave: (v) => ref
                      .read(settingsProvider.notifier)
                      .setHermesApiKey(v),
                ),
                const Divider(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Голос использует Whisper на Groq отдельно. B.ai-ключ '
                    'никогда не отправляется в Groq.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11),
                  ),
                ),
                _TextFieldSetting(
                  label: 'Groq API-ключ для Whisper',
                  initial: s.whisperApiKey,
                  hint: 'gsk_… (необязательно)',
                  obscure: true,
                  onSave: (v) => ref
                      .read(settingsProvider.notifier)
                      .setWhisperApiKey(v),
                ),
              ],
            ),
          ),
          const Divider(),

          const _SectionTitle('Поиск в интернете'),
          _TextFieldSetting(
            label: 'Свой SearXNG-инстанс',
            initial: s.searchSearxngUrl,
            hint: 'https://поиск.домен (пусто — публичные инстансы)',
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setSearchSearxngUrl(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.wifi_off),
            title: const Text('Не искать в интернете'),
            subtitle: const Text('Отвечать из знаний модели без веб-поиска'),
            value: s.searchOffline,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setSearchOffline(v),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Публичные инстансы часто блокируют запросы. Свой SearXNG '
              '(Docker: docker run -p 8080:8080 searxng/searxng) даёт '
              'стабильный поиск и свежие новости.',
              style: TextStyle(fontSize: 12, color: AppColors.textDim),
            ),
          ),
          const Divider(),

          const _SectionTitle('GitHub (верификация коммитов)'),
          _TextFieldSetting(
            label: 'GitHub owner (логин)',
            initial: s.githubOwner,
            hint: 'например: TimVoronkov',
            onSave: (v) => ref
                .read(settingsProvider.notifier)
                .setGithub(v, ref.read(settingsProvider).githubRepo),
          ),
          _TextFieldSetting(
            label: 'GitHub repo',
            initial: s.githubRepo,
            hint: 'например: system-hermes',
            onSave: (v) => ref
                .read(settingsProvider.notifier)
                .setGithub(ref.read(settingsProvider).githubOwner, v),
          ),
          const Divider(),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            onPressed: () => _resetAll(context, ref),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Сбросить все данные'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SettingsIntro extends StatelessWidget {
  final bool darkMode;
  final bool aiReady;
  final double pension;

  const _SettingsIntro({
    required this.darkMode,
    required this.aiReady,
    required this.pension,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: AppColors.violet),
              SizedBox(width: 9),
              Text(
                'Центр управления',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Главные параметры собраны здесь. Обычные данные сохраняются автоматически.',
            style: TextStyle(color: AppColors.textDim, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _SettingsPill(
                icon: darkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                text: darkMode ? 'ТЁМНАЯ ТЕМА' : 'СВЕТЛАЯ ТЕМА',
                color: AppColors.violet,
              ),
              _SettingsPill(
                icon: aiReady ? Icons.check_circle_outline : Icons.key_outlined,
                text: aiReady ? 'AI НАСТРОЕН' : 'НУЖЕН API-КЛЮЧ',
                color: aiReady ? AppColors.accent : AppColors.warning,
              ),
              _SettingsPill(
                icon: Icons.account_balance_wallet_outlined,
                text: '${fmt2(pension)} BYN / МЕС',
                color: AppColors.cyan,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SettingsPill({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: .35),
          ),
        ],
      ),
    );
  }
}

class _HermesConnectionCard extends ConsumerStatefulWidget {
  const _HermesConnectionCard();

  @override
  ConsumerState<_HermesConnectionCard> createState() =>
      _HermesConnectionCardState();
}

class _HermesConnectionCardState
    extends ConsumerState<_HermesConnectionCard> {
  late final TextEditingController _keyController;
  Timer? _debounce;
  bool _testing = false;
  bool _showKey = false;
  LlmConnectionResult? _result;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(
      text: ref.read(settingsProvider).hermesLlmApiKey,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final value = _keyController.text.trim();
    if (value != ref.read(settingsProvider).hermesLlmApiKey) {
      ref.read(settingsProvider.notifier).setHermesLlmApiKey(value);
    }
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    setState(() {
      _testing = true;
      _result = null;
    });
    final controller = ref.read(settingsProvider.notifier);
    await controller.setHermesLlmProvider(
      baseUrl: AppConstants.hermesLlmDefaultUrl,
      model: AppConstants.hermesLlmDefaultModel,
    );
    await controller.setHermesLlmApiKey(_keyController.text);
    final result = await testHermesLlmConnection(ref.read(settingsProvider));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final connected = settings.usesDirectLlm;
    final statusColor = connected ? AppColors.accent : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: .16),
            AppColors.cyan.withValues(alpha: .06),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.auto_awesome, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'B.ai · DeepSeek V4 Flash',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Основной интеллект Hermes Agent',
                      style: TextStyle(color: AppColors.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  connected ? 'ключ сохранён' : 'нужен ключ',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _keyController,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API-ключ B.ai',
              hintText: 'Вставь ключ из b.ai → API',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: _showKey ? 'Скрыть ключ' : 'Показать ключ',
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
            onChanged: (value) {
              _debounce?.cancel();
              _result = null;
              _debounce = Timer(const Duration(milliseconds: 500), () {
                ref
                    .read(settingsProvider.notifier)
                    .setHermesLlmApiKey(value);
              });
            },
          ),
          const SizedBox(height: 10),
          const Text(
            'Можно вставить ключ и с префиксом Bearer — Hermes исправит его '
            'сам. Ключ хранится только в настройках приложения.',
            style: TextStyle(color: AppColors.textDim, fontSize: 11, height: 1.35),
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_result!.ok ? AppColors.accent : AppColors.danger)
                    .withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _result!.message,
                style: TextStyle(
                  color: _result!.ok ? AppColors.accent : AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? 'Проверяю…' : 'Проверить API'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Открыть b.ai',
                onPressed: () => context.push('/web', extra: 'https://b.ai/'),
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          letterSpacing: -.1,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TextFieldSetting extends ConsumerStatefulWidget {
  final String label;
  final String initial;
  final String hint;
  final bool obscure;
  final ValueChanged<String> onSave;

  const _TextFieldSetting({
    required this.label,
    required this.initial,
    required this.hint,
    this.obscure = false,
    required this.onSave,
  });

  @override
  ConsumerState<_TextFieldSetting> createState() => _TextFieldSettingState();
}

class _TextFieldSettingState extends ConsumerState<_TextFieldSetting> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  Timer? _debounce;

  @override
  void didUpdateWidget(covariant _TextFieldSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Пресет провайдера изменил настройку — синхронизируем поле,
    // если пользователь в этот момент не редактирует его.
    if (widget.initial != oldWidget.initial &&
        !FocusScope.of(context).hasFocus) {
      _controller.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Уход с экрана раньше debounce-паузы — сохраняем последнее значение.
    final pending = _controller.text.trim();
    if (pending != widget.initial) {
      try {
        widget.onSave(pending);
      } catch (_) {}
    }
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final v = _controller.text.trim();
    if (v == widget.initial) return;
    widget.onSave(v);
    toast(context, 'Сохранено');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: TextField(
        controller: _controller,
        obscureText: widget.obscure,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          isDense: true,
        ),
        onChanged: (v) {
          // Автосохранение при вводе (через паузу) — чтобы значение
          // не потерялось, даже если уйти с экрана без Enter.
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 700), () {
            final val = _controller.text.trim();
            if (val == widget.initial) return;
            widget.onSave(val);
            toast(context, 'Сохранено');
          });
        },
        onSubmitted: (v) {
          _debounce?.cancel();
          widget.onSave(v.trim());
          toast(context, 'Сохранено');
        },
        onTapOutside: (_) => _save(),
      ),
    );
  }
}

/// Кнопка-пресет провайдера: подставляет URL и модель в настройках ИИ.
class _ProviderPreset extends ConsumerWidget {
  final String label;
  final String url;
  final String model;

  const _ProviderPreset({
    required this.label,
    required this.url,
    required this.model,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final active = s.hermesMode == HermesModes.direct &&
        s.hermesLlmUrl == url &&
        s.hermesLlmModel == model;
    return ActionChip(
      label: Text(label),
      backgroundColor:
          active ? AppColors.accent.withValues(alpha: 0.25) : null,
      labelStyle: TextStyle(
        color: active ? AppColors.accent : null,
        fontWeight: active ? FontWeight.w700 : null,
      ),
      onPressed: () async {
        await ref.read(settingsProvider.notifier).setHermesLlmProvider(
              baseUrl: url,
              model: model,
            );
        if (context.mounted) toast(context, '$label выбран для Hermes');
      },
    );
  }
}
