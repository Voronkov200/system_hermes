// Чат с единственным системным агентом Hermes.

import 'package:flutter/material.dart';
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
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
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

  @override
  Widget build(BuildContext context) {
    final hermes = ref.watch(chatProvider);
    final settings = ref.watch(settingsProvider);
    final offline = !settings.usesHermesServer && !settings.usesDirectLlm;
    final showQuick =
        hermes.messages.where((m) => m.role != 'system').length <= 3;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Text('Hermes Agent'),
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
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.warning,
                    size: 18,
                  ),
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
          if (offline)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      offline && settings.llmKey.isEmpty
                          ? 'Нет API-ключа B.ai — Hermes отвечает локальными '
                              'командами. Добавь ключ в настройках.'
                          : 'Модель не подключена: Hermes отвечает локальными '
                              'командами. API-ключ можно добавить в настройках.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/settings'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Настроить'),
                  ),
                ],
              ),
            ),
          if (!offline)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: .45),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_outlined,
                    color: AppColors.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      settings.usesHermesServer
                          ? 'Hermes подключён к собственному серверу'
                          : 'B.ai подключён · ${settings.hermesLlmModel}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Настройки подключения',
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.tune, size: 18),
                  ),
                ],
              ),
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
              padding: const EdgeInsets.all(16),
              itemCount: hermes.messages.length,
              itemBuilder: (context, index) => _MessageBubble(
                message: hermes.messages[index],
              ),
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

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isTool = message.role == 'system';
    final background = isTool
        ? const Color(0xFF10151D)
        : isUser
            ? const Color(0xFF0D2B22)
            : AppColors.surface;
    final border = isTool
        ? AppColors.cyan.withValues(alpha: .4)
        : isUser
            ? AppColors.accent.withValues(alpha: .4)
            : const Color(0xFF1E2836);
    final label = isUser
        ? 'ТЫ'
        : isTool
            ? 'TOOL'
            : 'HERMES';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * .85,
        ),
        decoration: BoxDecoration(
          color: background,
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
                child: Icon(Icons.image, color: AppColors.warning, size: 40),
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
