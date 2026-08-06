// Чат-хаб: Hermes Agent (инструменты) и Настя (ИИ-компаньон).
//
// Переключатель в AppBar меняет собеседника. У Насти: аватар/фон из фото,
// уровень отношений, полоса симпатии и блокировка после срывов.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/companion_catalog.dart';
import '../../data/models.dart';
import '../../services/companion_service.dart';
import '../../services/hermes_service.dart';
import '../../services/settings_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _nastya = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _scrollDown();
    if (_nastya) {
      await ref.read(companionProvider.notifier).send(text);
    } else {
      await ref.read(chatProvider.notifier).send(text);
    }
    _scrollDown();
  }

  /// Фото Насти: выбранное из галереи, либо фото по умолчанию (её TikTok).
  Widget _photoOrFallback(String path) {
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    return Image.asset(
      AppConstants.nastyaDefaultPhoto,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hermes = ref.watch(chatProvider);
    final nastya = ref.watch(companionProvider);
    final settings = ref.watch(settingsProvider);

    // Офлайн-режим: ИИ не подключён (нет API-ключа / URL сервера Hermes).
    final llmOffline = _nastya
        ? settings.companionKey.isEmpty
        : (settings.hermesUrl.trim().isEmpty && settings.llmKey.isEmpty);

    final pending = _nastya ? null : hermes.pendingPhotoTask;
    final thinking = _nastya ? nastya.thinking : hermes.thinking;
    final messages = _nastya ? nastya.messages : hermes.messages;

    return Scaffold(
      appBar: AppBar(
        title: _nastya ? _NastyaTitle(companion: nastya) : _hermesTitle(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.terminal, size: 16),
                  label: Text('Hermes'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.favorite, size: 16),
                  label: Text('Настя'),
                ),
              ],
              selected: {_nastya},
              onSelectionChanged: (sel) {
                setState(() => _nastya = sel.first);
                _scrollDown();
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Фон: фото Насти (выбранное или по умолчанию из её TikTok),
          // прикрытое полупрозрачным светлым градиентом — фон светлый,
          // но фото остаётся видимым.
          if (_nastya)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _photoOrFallback(nastya.avatarPath),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xB3FFF6EC),
                          Color(0x99FFE7F3),
                          Color(0x8CDCEAFB),
                        ],
                        stops: [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Column(
            children: [
              // Запрос фото-верификации (только Hermes)
              if (pending != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.camera_alt_outlined,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hermes.pendingPhotoDescription ??
                              'Требуется фото-подтверждение',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(chatProvider.notifier).pickAndSendPhoto(),
                        child: const Text('Отправить фото'),
                      ),
                    ],
                  ),
                ),
              // Блокировка Насти после срыва
              if (_nastya && nastya.blocked)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.danger),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_clock, color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Настя обижена после срыва. Чат разблокируется: '
                          '${fmtDateTime(nastya.blockedUntil ?? DateTime.now())}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              // Офлайн-режим: ИИ не подключён — отвечают скрипты.
              if (llmOffline)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _nastya
                              ? 'ИИ не подключён: отвечаю по скрипту. '
                                  'Впиши API-ключ: Настройки → ИИ и компаньон.'
                              : 'ИИ не подключён: Hermes отвечает по скрипту. '
                                  'Впиши API-ключ: Настройки → ИИ и компаньон.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return _MessageBubble(
                        message: m, nastyaMode: _nastya);
                  },
                ),
              ),
              // Панель ввода
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: Color(0xFF1E2836))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          onSubmitted: (_) => _send(),
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: _nastya
                                ? 'Сообщение для Насти…'
                                : 'Сообщение для Hermes…',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: thinking ? null : _send,
                        icon: thinking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        color: _nastya ? AppColors.violet : AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hermesTitle() {
    return const Row(
      children: [
        Icon(Icons.terminal, color: AppColors.accent, size: 20),
        SizedBox(width: 8),
        Text('Hermes Agent'),
      ],
    );
  }
}

/// Заголовок AppBar для Насти: аватар, имя, уровень отношений и симпатия.
class _NastyaTitle extends StatelessWidget {
  final CompanionState companion;

  const _NastyaTitle({required this.companion});

  @override
  Widget build(BuildContext context) {
    final level = levelForAffinity(companion.affinity);
    final progress = levelProgress(companion.affinity);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        _NastyaAvatar(
          path: companion.avatarPath,
          size: 34,
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Настя',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Text(
                  level.name,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.violet),
                ),
              ],
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: 110,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: isDark
                      ? const Color(0xFF1E2836)
                      : Colors.black12,
                  valueColor: const AlwaysStoppedAnimation(AppColors.violet),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Круглый аватар Насти: фото (выбранное или по умолчанию).
class _NastyaAvatar extends StatelessWidget {
  final String path;
  final double size;

  const _NastyaAvatar({
    required this.path,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (path.isNotEmpty && File(path).existsSync()) {
      return ClipOval(
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return ClipOval(
      child: Image.asset(
        AppConstants.nastyaDefaultPhoto,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.violet, AppColors.danger],
            ),
          ),
          child: Center(
            child: Text(
              'Н',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.45,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool nastyaMode;

  const _MessageBubble({required this.message, required this.nastyaMode});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isTool = message.role == 'system';
    final isNastya = message.role == 'nastya';

    final Color bg;
    if (isTool) {
      bg = const Color(0xFF10151D);
    } else if (isUser) {
      bg = const Color(0xFF0D2B22);
    } else if (isNastya) {
      bg = const Color(0xFF221536);
    } else {
      bg = AppColors.surface;
    }

    final Color border;
    if (isTool) {
      border = AppColors.cyan.withValues(alpha: 0.4);
    } else if (isUser) {
      border = AppColors.accent.withValues(alpha: 0.4);
    } else if (isNastya) {
      border = AppColors.violet.withValues(alpha: 0.5);
    } else {
      border = const Color(0xFF1E2836);
    }

    final String label;
    if (isUser) {
      label = 'ТЫ';
    } else if (isTool) {
      label = 'TOOL';
    } else if (isNastya) {
      label = 'НАСТЯ';
    } else {
      label = 'HERMES';
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 2),
            bottomRight: Radius.circular(isUser ? 2 : 12),
          ),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imagePath != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Icon(
                  Icons.image,
                  color: AppColors.warning,
                  size: 40,
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontFamily: isTool ? 'monospace' : null,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$label • ${fmtTime(message.date)}',
              style: const TextStyle(color: AppColors.textDim, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
