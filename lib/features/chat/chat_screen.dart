// Чат с единственным системным агентом Hermes.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/hermes_service.dart';
import '../../services/journal_service.dart';
import '../../services/settings_service.dart';
import '../../services/whisper_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final VoiceTranscriber _voice = VoiceTranscriber();
  bool _recording = false;
  bool _transcribing = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _scrollDown();
    await ref.read(chatProvider.notifier).send(text);
    _scrollDown();
  }

  Future<void> _toggleVoice() async {
    if (_transcribing) return;

    if (!_recording) {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _snack('Нет доступа к микрофону. Разреши его в настройках телефона.');
        return;
      }
      try {
        await _voice.startRecording();
        if (!mounted) return;
        setState(() => _recording = true);
        _snack('Запись идёт. Нажми ещё раз, чтобы закончить.');
      } catch (error) {
        _snack('Не удалось начать запись: $error');
      }
      return;
    }

    setState(() {
      _recording = false;
      _transcribing = true;
    });
    final path = await _voice.stopRecording();
    if (!mounted) return;
    if (path == null) {
      setState(() => _transcribing = false);
      _snack('Запись не сохранилась.');
      return;
    }

    try {
      final key = ref.read(settingsProvider).whisperApiKey.trim();
      if (key.isEmpty) {
        throw Exception(
          'не задан отдельный Groq API-ключ для Whisper в настройках',
        );
      }
      final text = await _voice.transcribe(path, key);
      if (!mounted) return;
      await _confirmVoiceText(text);
    } catch (error) {
      _snack('Транскрибация не удалась: $error');
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _confirmVoiceText(String text) async {
    final controller = TextEditingController(text: text);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Я распознал:'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Проверь и поправь текст',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    controller.dispose();
    final confirmed = (result ?? '').trim();
    if (confirmed.isEmpty || !mounted) return;
    ref.read(journalProvider.notifier).add(
          type: 'voice',
          source: 'user',
          title: _shortTitle(confirmed),
          text: confirmed,
        );
    _input.text = confirmed;
    await _send();
  }

  String _shortTitle(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return clean.length > 60 ? '${clean.substring(0, 60)}…' : clean;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('Скопировано');
  }

  String _statusSubtitle(SettingsState s, bool offline) {
    if (offline) {
      return s.llmKey.isEmpty
          ? 'офлайн · нужен API-ключ'
          : 'офлайн · локальные команды';
    }
    if (s.usesHermesServer) return 'собственный сервер';
    return 'b.ai · ${s.hermesLlmModel}';
  }

  @override
  Widget build(BuildContext context) {
    final hermes = ref.watch(chatProvider);
    final settings = ref.watch(settingsProvider);
    final offline = !settings.usesHermesServer && !settings.usesDirectLlm;
    final showQuick =
        hermes.messages.where((m) => m.role != 'system').length <= 3;
    final showTyping = hermes.thinking;

    ref.listen(chatProvider.select((s) => s.thinking), (prev, next) {
      if (next == true) _scrollDown();
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const _ChatAvatar(role: 'hermes'),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Hermes Agent',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 1),
                Text(
                  _statusSubtitle(settings, offline),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Журнал изменений',
            onPressed: () => context.push('/journal'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (hermes.pendingPhotoTask != null)
            _StatusBanner(
              icon: Icons.camera_alt_outlined,
              color: AppColors.warning,
              text: hermes.pendingPhotoDescription ??
                  'Требуется фото-подтверждение',
              actionLabel: 'Отправить фото',
              onAction: ref.read(chatProvider.notifier).pickAndSendPhoto,
            ),
          if (offline)
            _StatusBanner(
              icon: Icons.cloud_off,
              color: AppColors.warning,
              text: offline && settings.llmKey.isEmpty
                  ? 'Нет API-ключа B.ai — Hermes отвечает локальными '
                      'командами. Добавь ключ, чтобы включить модель.'
                  : 'Модель не подключена: Hermes отвечает локальными '
                      'командами. API-ключ можно добавить в настройках.',
              actionLabel: 'Настроить',
              onAction: () => context.push('/settings'),
            ),
          if (showQuick)
            _CapabilityChips(
              onPick: (template) {
                _input.text = template;
                _input.selection = TextSelection.collapsed(
                  offset: template.length,
                );
              },
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              itemCount: hermes.messages.length + (showTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= hermes.messages.length) {
                  return const _TypingBubble();
                }
                return _MessageBubble(
                  message: hermes.messages[index],
                  onCopy: _copy,
                );
              },
            ),
          ),
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
                  IconButton(
                    onPressed: hermes.thinking || _transcribing
                        ? null
                        : _toggleVoice,
                    tooltip: _recording
                        ? 'Остановить запись'
                        : 'Голосовое сообщение',
                    icon: _transcribing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _recording ? Icons.stop_circle : Icons.mic_none,
                            color: _recording
                                ? AppColors.danger
                                : AppColors.textDim,
                          ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onSubmitted: (_) => _send(),
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: _recording
                            ? 'Запись… нажми стоп для транскрибации'
                            : 'Сообщение для Hermes…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: hermes.thinking ? null : _send,
                    icon: hermes.thinking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    color: AppColors.accent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Аватары и баннеры
// =====================================================================

class _ChatAvatar extends StatelessWidget {
  final String role;

  const _ChatAvatar({required this.role});

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isUser
              ? const [Color(0xFF1F7A5C), AppColors.accent]
              : const [Color(0xFF1E5F86), AppColors.cyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isUser
              ? AppColors.accent.withValues(alpha: .5)
              : AppColors.cyan.withValues(alpha: .5),
          width: 1.2,
        ),
      ),
      child: Icon(
        isUser ? Icons.person_rounded : Icons.smart_toy_rounded,
        size: 18,
        color: Colors.white,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: color,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _CapabilityChips extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _CapabilityChips({required this.onPick});

  @override
  Widget build(BuildContext context) {
    const items = <(String, IconData, String)>[
      ('Учебник', Icons.menu_book_rounded, 'Разбери параграф из учебника по теме: '),
      ('Поиск', Icons.travel_explore_rounded, 'Найди информацию о: '),
      ('Задачи в Плане', Icons.checklist_rounded, 'Составь задачи по теме: '),
      ('Конспект', Icons.description_rounded, 'Сделай конспект по: '),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Чем помочь?',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, icon, template) in items)
                ActionChip(
                  avatar: Icon(icon, size: 16, color: AppColors.accent),
                  label: Text(label),
                  labelStyle: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: AppColors.accent.withValues(alpha: .35),
                  ),
                  backgroundColor: AppColors.accent.withValues(alpha: .10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onPressed: () => onPick(template),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Пузырь сообщения
// =====================================================================

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final ValueChanged<String> onCopy;

  const _MessageBubble({required this.message, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    if (message.role == 'system') {
      return message.toolName != null
          ? _ToolCard(message: message)
          : _SystemNote(text: message.text, date: message.date);
    }
    return _ChatBubble(message: message, onCopy: onCopy);
  }
}

/// Обычный пузырь (пользователь слева/справа, Hermes слева).
class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final ValueChanged<String> onCopy;

  const _ChatBubble({required this.message, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const _ChatAvatar(role: 'hermes'),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => onCopy(message.text),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * .78,
                ),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 7),
                decoration: BoxDecoration(
                  gradient: isUser
                      ? LinearGradient(
                          colors: [
                            AppColors.accent.withValues(alpha: .16),
                            AppColors.accent.withValues(alpha: .05),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: isUser ? null : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                  border: Border.all(
                    color: isUser
                        ? AppColors.accent.withValues(alpha: .35)
                        : AppColors.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.imagePath != null) ...[
                      const Icon(
                        Icons.image_outlined,
                        color: AppColors.warning,
                        size: 34,
                      ),
                      const SizedBox(height: 6),
                    ],
                    MarkdownBody(
                      data: message.text,
                      selectable: true,
                      styleSheet: _markdownStyle(context),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isUser ? 'ТЫ' : 'HERMES',
                          style: TextStyle(
                            color: isUser
                                ? AppColors.accent.withValues(alpha: .8)
                                : AppColors.cyan.withValues(alpha: .8),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .6,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          fmtTime(message.date),
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            const _ChatAvatar(role: 'user'),
          ],
        ],
      ),
    );
  }
}

/// Карточка вызова инструмента (tool call), по центру.
class _ToolCard extends StatelessWidget {
  final ChatMessage message;

  const _ToolCard({required this.message});

  Color get _color => switch (message.toolStatus) {
        'error' => AppColors.danger,
        'pending' => AppColors.warning,
        _ => AppColors.accent,
      };

  IconData get _icon => switch (message.toolStatus) {
        'error' => Icons.error_outline,
        'pending' => Icons.sync,
        _ => Icons.check_circle_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * .92,
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1219),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _color.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon, size: 15, color: _color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Инструмент · ${message.toolName}',
                      style: TextStyle(
                        color: _color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    message.toolStatus == 'pending' ? '…' : fmtTime(message.date),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                message.text,
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Обычная системная заметка по центру.
class _SystemNote extends StatelessWidget {
  final String text;
  final DateTime date;

  const _SystemNote({required this.text, required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * .85,
          ),
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text.truncate(160),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
          ),
        ),
      ),
    );
  }
}

/// Анимация «Hermes думает…».
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 44, right: 44, bottom: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.5),
                          child: Opacity(
                            opacity: _dotOpacity(t, i),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(width: 9),
              const Text(
                'Hermes думает…',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _dotOpacity(double t, int i) {
    final wave = (math.sin(t * 2 * math.pi - i * 0.9) + 1) / 2;
    return 0.25 + 0.75 * wave;
  }
}

// =====================================================================
// Markdown-стиль
// =====================================================================

MarkdownStyleSheet _markdownStyle(BuildContext context) {
  final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
  return base.copyWith(
    p: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.45),
    strong: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w800,
    ),
    em: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 15,
      height: 1.45,
      fontStyle: FontStyle.italic,
    ),
    h1: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w900,
    ),
    h2: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w800,
    ),
    h3: const TextStyle(
      color: AppColors.cyan,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
    listBullet: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14,
      height: 1.45,
    ),
    blockquote: const TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
    blockquoteDecoration: const BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.all(Radius.circular(8)),
      border: Border(left: BorderSide(color: AppColors.cyan, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.all(10),
    code: const TextStyle(
      color: AppColors.cyan,
      fontFamily: 'monospace',
      fontSize: 13,
      backgroundColor: AppColors.surfaceAlt,
    ),
    codeblockDecoration: const BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.all(Radius.circular(8)),
      border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    a: const TextStyle(color: AppColors.cyan, fontSize: 14),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
  );
}

// =====================================================================
// Утилиты
// =====================================================================

extension _Truncate on String {
  String truncate(int max) {
    if (length <= max) return this;
    return '${substring(0, max)}…';
  }
}
