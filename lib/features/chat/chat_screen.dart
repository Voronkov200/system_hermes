// Чат-хаб с Hermes Agent: сообщения, tool calling, фото-верификация.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/hermes_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

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
    await ref.read(chatProvider.notifier).send(text);
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final pending = chat.pendingPhotoTask;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Text('Hermes Agent'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Запрос фото-верификации
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
                      chat.pendingPhotoDescription ?? 'Требуется фото-подтверждение',
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
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: chat.messages.length,
              itemBuilder: (context, i) {
                final m = chat.messages[i];
                return _MessageBubble(message: m);
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
                      decoration: const InputDecoration(
                        hintText: 'Сообщение для Hermes…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: chat.thinking ? null : _send,
                    icon: chat.thinking
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

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isTool = message.role == 'system';

    final Color bg;
    if (isTool) {
      bg = const Color(0xFF10151D);
    } else if (isUser) {
      bg = const Color(0xFF0D2B22);
    } else {
      bg = AppColors.surface;
    }

    final Color border;
    if (isTool) {
      border = AppColors.cyan.withValues(alpha: 0.4);
    } else if (isUser) {
      border = AppColors.accent.withValues(alpha: 0.4);
    } else {
      border = const Color(0xFF1E2836);
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
              '${isUser ? 'ТЫ' : isTool ? 'TOOL' : 'HERMES'} • ${fmtTime(message.date)}',
              style: const TextStyle(color: AppColors.textDim, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
