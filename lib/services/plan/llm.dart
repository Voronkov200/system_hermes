// Вызов LLM (Groq-совместимый endpoint) для модулей «План»:
// Поиск (ответ с цитатами) и Документы (конспекты, вопросы).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../settings_service.dart';

/// Простой вызов chat/completions (без stream и инструментов).
/// Возвращает текст ответа или бросает Exception с понятной причиной.
Future<String> llmComplete(
  WidgetRef ref, {
  required String system,
  required String user,
  int maxTokens = 1500,
  int timeoutSeconds = 90,
}) async {
  final s = ref.read(settingsProvider);
  final apiKey = s.llmKey.trim();
  if (apiKey.isEmpty) {
    throw Exception('Не задан API-ключ LLM: вставь ключ Groq '
        'в Настройках (Hermes) и попробуй ещё раз.');
  }
  final apiUrl = s.companionApiUrl.trim().isNotEmpty
      ? s.companionApiUrl.trim()
      : 'https://api.groq.com/openai/v1/chat/completions';
  final model = s.companionModel.trim().isNotEmpty
      ? s.companionModel.trim()
      : 'llama-3.3-70b-versatile';

  final res = await http
      .post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          'temperature': 0.4,
          'max_tokens': maxTokens,
        }),
      )
      .timeout(Duration(seconds: timeoutSeconds));

  if (res.statusCode != 200) {
    final reason = switch (res.statusCode) {
      401 => 'неверный API-ключ (401)',
      404 => 'неверный URL или модель (404)',
      429 => 'превышен лимит запросов (429)',
      _ => 'ошибка сервера ИИ (HTTP ${res.statusCode})',
    };
    throw Exception(reason);
  }

  final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final choices = data['choices'] as List? ?? const [];
  if (choices.isEmpty) throw Exception('Пустой ответ API');
  final message = (choices.first as Map)['message'] as Map<String, dynamic>;
  final content = message['content'] as String? ?? '';
  if (content.trim().isEmpty) throw Exception('Пустой ответ модели');
  return content.trim();
}
