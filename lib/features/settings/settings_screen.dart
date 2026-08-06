// Экран настроек: тема, пенсия, Vault, Hermes Agent, GitHub, сброс.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/bank_service.dart';
import '../../services/companion_service.dart';
import '../../services/habits_service.dart';
import '../../services/hermes_service.dart';
import '../../services/mining_service.dart';
import '../../services/obsidian_service.dart';
import '../../services/settings_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _resetAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Сбросить все данные?'),
        content: const Text(
            'Будут удалены: счета и транзакции, ферма, привычки, история чата. '
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
    await ref.read(miningProvider.notifier).reset();
    await ref.read(habitsProvider.notifier).reset();
    await ref.read(chatProvider.notifier).reset();
    await ref.read(companionProvider.notifier).reset();
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

          const _SectionTitle('Центральный Банк'),
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
            title: const Text('Сумма пенсии (BYN)'),
            subtitle: Text(fmt2(s.pensionAmount)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final controller = TextEditingController(
                  text: fmt2(s.pensionAmount));
              final v = await showDialog<double>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: const Text('Сумма пенсии'),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                          ctx,
                          double.tryParse(controller.text.replaceAll(',', '.'))),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
              if (v != null && v > 0) {
                await ref.read(settingsProvider.notifier).setPensionAmount(v);
              }
            },
          ),
          ListTile(
            title: const Text('Валюта твердых активов'),
            subtitle: Text(s.assetsCurrency),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'USD', label: Text('USD')),
                ButtonSegment(value: 'EUR', label: Text('EUR')),
              ],
              selected: {s.assetsCurrency},
              onSelectionChanged: (sel) => ref
                  .read(settingsProvider.notifier)
                  .setAssetsCurrency(sel.first),
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
              'Ключ Hermes используется и Настей, если её собственный ключ не задан.',
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
            label: 'API ключ Hermes',
            initial: s.hermesApiKey,
            hint: 'опционально',
            obscure: true,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setHermesApiKey(v),
          ),
          const Divider(),

          const _SectionTitle('Настя (ИИ-компаньон)'),
          ListTile(
            leading: _AvatarPreview(path: ref.watch(companionProvider).avatarPath),
            title: const Text('Фото Насти'),
            subtitle: const Text('Аватар и фон в чате. '
                'По умолчанию — фото с её TikTok'),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final path = await ref
                    .read(companionProvider.notifier)
                    .pickAvatar();
                if (context.mounted) {
                  toast(context,
                      path == null ? 'Фото не выбрано' : 'Фото Насти обновлено');
                }
              },
              child: const Text('Выбрать'),
            ),
          ),
          _TextFieldSetting(
            label: 'API URL (OpenCode Zen / OpenAI)',
            initial: s.companionApiUrl,
            hint: AppConstants.companionDefaultUrl,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setCompanionApiUrl(v),
          ),
          _TextFieldSetting(
            label: 'API ключ',
            initial: s.companionApiKey,
            hint: 'sk-… из OpenCode Zen (без ключа — офлайн-режим)',
            obscure: true,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setCompanionApiKey(v),
          ),
          _TextFieldSetting(
            label: 'Модель',
            initial: s.companionModel,
            hint: AppConstants.companionDefaultModel,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setCompanionModel(v),
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

/// Кружок-превью фото Насти (выбранное или по умолчанию).
class _AvatarPreview extends StatelessWidget {
  final String path;

  const _AvatarPreview({required this.path});

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    Widget image;
    if (path.isNotEmpty && File(path).existsSync()) {
      image = Image.file(File(path), fit: BoxFit.cover);
    } else {
      image = Image.asset(
        AppConstants.nastyaDefaultPhoto,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.favorite,
          color: AppColors.violet,
          size: 20,
        ),
      );
    }
    return ClipOval(
      child: SizedBox(width: size, height: size, child: image),
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        onSubmitted: (v) {
          widget.onSave(v.trim());
          toast(context, 'Сохранено');
        },
        onTapOutside: (_) {
          final v = _controller.text.trim();
          if (v == widget.initial) return;
          widget.onSave(v);
          toast(context, 'Сохранено');
        },
      ),
    );
  }
}
