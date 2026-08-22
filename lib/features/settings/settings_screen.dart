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
        padding: const EdgeInsets.all(16),
        children: [
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

          const _SectionTitle('Hermes Agent'),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Можно подключить собственный сервер Hermes или использовать '
              'OpenAI-совместимую модель напрямую.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ),
          _TextFieldSetting(
            label: 'URL сервера Hermes',
            initial: s.hermesUrl,
            hint: 'https://your-server.example/api/hermes',
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setHermesUrl(v),
          ),
          _TextFieldSetting(
            label: 'Ключ сервера Hermes',
            initial: s.hermesApiKey,
            hint: 'не нужен, если сервер не используется',
            obscure: true,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setHermesApiKey(v),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              'Модель Hermes. Без ключа агент работает в локальном '
              'офлайн-режиме. '
              'Бесплатный ключ Groq: console.groq.com → API Keys.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Wrap(
              spacing: 8,
              children: [
                _ProviderPreset(
                  label: 'Groq',
                  url: 'https://api.groq.com/openai/v1/chat/completions',
                  model: 'llama-3.3-70b-versatile',
                ),
                _ProviderPreset(
                  label: 'OpenCode Zen',
                  url: 'https://opencode.ai/zen/v1/chat/completions',
                  model: 'deepseek-v4-flash-free',
                ),
                _ProviderPreset(
                  label: 'OpenRouter',
                  url: 'https://openrouter.ai/api/v1/chat/completions',
                  model: 'meta-llama/llama-3.3-70b-instruct:free',
                ),
              ],
            ),
          ),
          _TextFieldSetting(
            label: 'URL модели Hermes',
            initial: s.hermesLlmUrl,
            hint: AppConstants.hermesLlmDefaultUrl,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setHermesLlmUrl(v),
          ),
          _TextFieldSetting(
            label: 'API-ключ модели Hermes',
            initial: s.hermesLlmApiKey,
            hint: 'gsk_… из console.groq.com (без ключа — офлайн-режим)',
            obscure: true,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setHermesLlmApiKey(v),
          ),
          _TextFieldSetting(
            label: 'Модель Hermes',
            initial: s.hermesLlmModel,
            hint: AppConstants.hermesLlmDefaultModel,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setHermesLlmModel(v),
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
          fontSize: 12,
          letterSpacing: 1,
          color: AppColors.cyan,
          fontWeight: FontWeight.w700,
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
    if (pending.isNotEmpty && pending != widget.initial) {
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
    final active = s.hermesLlmUrl == url && s.hermesLlmModel == model;
    return ActionChip(
      label: Text(label),
      backgroundColor:
          active ? AppColors.accent.withValues(alpha: 0.25) : null,
      labelStyle: TextStyle(
        color: active ? AppColors.accent : null,
        fontWeight: active ? FontWeight.w700 : null,
      ),
      onPressed: () {
        ref.read(settingsProvider.notifier).setHermesLlmUrl(url);
        ref.read(settingsProvider.notifier).setHermesLlmModel(model);
        if (context.mounted) toast(context, '$label: URL и модель подставлены');
      },
    );
  }
}
