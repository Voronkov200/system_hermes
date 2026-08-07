// Транскрибация голоса: запись с микрофона → Whisper (Groq API).
//
// Использует тот же API-ключ, что и чат (Groq): модель whisper-large-v3
// доступна бесплатно на api.groq.com/openai/v1/audio/transcriptions.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceTranscriber {
  static const _groqTranscribeUrl =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  final AudioRecorder _recorder = AudioRecorder();

  bool _recording = false;
  String _filePath = '';

  bool get isRecording => _recording;

  /// Освобождение ресурсов микрофона (вызывается при закрытии чата).
  Future<void> dispose() async {
    if (_recording) {
      _recording = false;
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    await _recorder.dispose();
  }

  /// Начало записи с микрофона.
  Future<void> startRecording() async {
    if (_recording) return;
    final dir = await getApplicationDocumentsDirectory();
    _filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
      path: _filePath,
    );
    _recording = true;
  }

  /// Остановка записи и возврат пути к файлу.
  Future<String?> stopRecording() async {
    if (!_recording) return null;
    _recording = false;
    await _recorder.stop();
    if (File(_filePath).existsSync()) return _filePath;
    return null;
  }

  /// Транскрибация аудиофайла через Whisper на Groq.
  Future<String> transcribe(String filePath, String apiKey) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('Запись не сохранилась, попробуй ещё раз.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_groqTranscribeUrl),
    )
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'whisper-large-v3'
      ..fields['language'] = 'ru'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      final reason = switch (res.statusCode) {
        401 => 'неверный API-ключ (401)',
        413 => 'запись слишком большая (413)',
        429 => 'превышен лимит запросов (429)',
        _ => 'ошибка сервера (HTTP ${res.statusCode})',
      };
      throw Exception(reason);
    }

    final Map<String, dynamic> data;
    try {
      data = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      throw Exception('Некорректный ответ от Whisper');
    }
    final text = (data['text'] as String? ?? '').trim();
    if (text.isEmpty) throw Exception('Речь не распознана — говори громче.');
    return text;
  }
}
