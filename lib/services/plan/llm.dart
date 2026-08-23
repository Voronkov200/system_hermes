// Вызов OpenAI-совместимой LLM для модулей «План»:
// Поиск (ответ с цитатами) и Документы (конспекты, вопросы).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../llm_endpoint.dart';
import '../settings_service.dart';

/// Ошибка HTTP от LLM-провайдера с кодом ответа — retry (раздел 6,
/// задача 2) повторяет вызовы с 429/5xx.
class LlmHttpException implements Exception {
  final int statusCode;
  final String message;

  const LlmHttpException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Простой вызов chat/completions (без stream и инструментов).
/// Возвращает текст ответа или бросает Exception с понятной причиной.
/// Настройки передаются параметром — не зависит от типа ref
/// (работает и из виджетов с [WidgetRef], и из Notifier'ов с [Ref]).
Future<String> llmComplete(
  SettingsState s, {
  required String system,
  required String user,
  int maxTokens = 1500,
  int timeoutSeconds = 90,
  double temperature = 0.4,
  String? model,
}) async {
  final apiKey = s.llmKey.trim();
  if (apiKey.isEmpty) {
    throw Exception('Не задан API-ключ LLM: вставь ключ B.ai '
        'в Настройках (Hermes) и попробуй ещё раз.');
  }
  final apiUrl = s.hermesLlmUrl.trim().isNotEmpty
      ? s.hermesLlmUrl.trim()
      : AppConstants.hermesLlmDefaultUrl;
  final usedModel = model?.trim().isNotEmpty == true
      ? model!.trim()
      : s.hermesLlmModel.trim().isNotEmpty
          ? s.hermesLlmModel.trim()
          : AppConstants.hermesLlmDefaultModel;

  final res = await http
      .post(
        openAiChatCompletionsUri(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': usedModel,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          'temperature': temperature,
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
    throw LlmHttpException(res.statusCode, reason);
  }

  final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final choices = data['choices'] as List? ?? const [];
  if (choices.isEmpty) throw Exception('Пустой ответ API');
  final message = (choices.first as Map)['message'] as Map<String, dynamic>;
  final content = message['content'] as String? ?? '';
  if (content.trim().isEmpty) throw Exception('Пустой ответ модели');
  return content.trim();
}
