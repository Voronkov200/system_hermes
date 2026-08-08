// Экран "Запись лекции": запись с микрофона → транскрибация (Whisper на Groq)
// → сохранение как источника в модуле «Документы».

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/plan/docs_service.dart';
import '../../services/settings_service.dart';
import '../../services/whisper_service.dart';

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  final VoiceTranscriber _transcriber = VoiceTranscriber();

  bool _recording = false;
  bool _busy = false;
  String? _error;
  String? _result;
  Timer? _ticker;
  int _elapsed = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _transcriber.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      await _stopAndTranscribe();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _error = 'Нет доступа к микрофону — разреши в настройках');
      return;
    }
    setState(() {
      _recording = true;
      _error = null;
      _result = null;
      _elapsed = 0;
    });
    try {
      await _transcriber.startRecording();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed++);
      });
    } catch (e) {
      setState(() {
        _recording = false;
        _error = 'Не удалось начать запись: $e';
      });
    }
  }

  Future<void> _stopAndTranscribe() async {
    _ticker?.cancel();
    setState(() {
      _recording = false;
      _busy = true;
      _error = null;
    });
    final path = await _transcriber.stopRecording();
    if (!mounted) return;
    if (path == null) {
      setState(() {
        _busy = false;
        _error = 'Запись не сохранилась — попробуй ещё раз';
      });
      return;
    }
    try {
      final key = ref.read(settingsProvider).llmKey.trim();
      if (key.isEmpty) {
        throw Exception('Не задан API-ключ LLM: вставь ключ Groq '
            'в Настройках (Hermes)');
      }
      final text = await _transcriber.transcribe(path, key);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = text;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _saveToDocs() async {
    final titleController = TextEditingController(
      text: 'Лекция ${fmtDateTime(DateTime.now())}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сохранить как источник'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название лекции'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(docsProvider.notifier).add(
            title: titleController.text,
            sourceType: 'transcribe',
            content: _result ?? '',
          );
      if (!mounted) return;
      toast(context, 'Лекция сохранена в Документы');
      Navigator.of(context).pop();
    }
  }

  String get _elapsedText {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Запись лекции')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 8),
          const Text(
            'Запиши лекцию или объяснение — Whisper превратит речь в текст, '
            'и он станет источником в «Документах» (вопросы и конспекты).',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Center(
            child: _busy
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: _toggle,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _recording
                            ? AppColors.danger.withValues(alpha: 0.15)
                            : AppColors.accent.withValues(alpha: 0.12),
                        border: Border.all(
                          color: _recording ? AppColors.danger : AppColors.accent,
                          width: 3,
                        ),
                      ),
                      child: Icon(
                        _recording ? Icons.stop : Icons.mic,
                        size: 48,
                        color: _recording ? AppColors.danger : AppColors.accent,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Center(
            child: _busy
                ? const Text('Распознаю речь…',
                    style: TextStyle(color: AppColors.textDim))
                : _recording
                    ? Text(
                        'Идёт запись: $_elapsedText',
                        style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      )
                    : Text(
                        _result == null ? 'Нажми — начнётся запись' : 'Готово',
                        style: const TextStyle(color: AppColors.textDim),
                      ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  _result!,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saveToDocs,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Сохранить в Документы'),
            ),
          ],
        ],
      ),
    );
  }
}
