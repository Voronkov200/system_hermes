import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'llm_endpoint.dart';
import 'settings_service.dart';

class LlmConnectionResult {
  final bool ok;
  final String message;
  final int? statusCode;
  final int elapsedMs;

  const LlmConnectionResult({
    required this.ok,
    required this.message,
    this.statusCode,
    this.elapsedMs = 0,
  });
}

/// Выполняет минимальный запрос без пользовательских данных и инструментов.
/// Это проверяет одновременно URL, ключ и доступ к выбранной модели.
Future<LlmConnectionResult> testHermesLlmConnection(
  SettingsState settings, {
  http.Client? client,
}) async {
  final key = normalizeApiKey(settings.llmKey);
  if (key.isEmpty) {
    return const LlmConnectionResult(
      ok: false,
      message: 'Сначала вставь API-ключ B.ai.',
    );
  }
  final baseUrl = settings.hermesLlmUrl.trim().isEmpty
      ? AppConstants.hermesLlmDefaultUrl
      : settings.hermesLlmUrl.trim();
  final model = settings.hermesLlmModel.trim().isEmpty
      ? AppConstants.hermesLlmDefaultModel
      : settings.hermesLlmModel.trim();
  final stopwatch = Stopwatch()..start();
  final ownClient = client == null;
  final httpClient = client ?? http.Client();

  try {
    final response = await httpClient
        .post(
          openAiChatCompletionsUri(baseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': model,
            'messages': const [
              {
                'role': 'user',
                'content': 'Ответь одним словом: OK',
              },
            ],
            'temperature': 0,
            'max_tokens': 8,
          }),
        )
        .timeout(const Duration(seconds: 30));
    stopwatch.stop();

    if (response.statusCode != 200) {
      return LlmConnectionResult(
        ok: false,
        statusCode: response.statusCode,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: llmApiErrorMessage(
          response.statusCode,
          utf8.decode(response.bodyBytes, allowMalformed: true),
        ),
      );
    }

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map || decoded['choices'] is! List) {
      return LlmConnectionResult(
        ok: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: 'API ответил, но формат ответа не распознан.',
      );
    }
    return LlmConnectionResult(
      ok: true,
      elapsedMs: stopwatch.elapsedMilliseconds,
      message: 'Подключено: $model · ${stopwatch.elapsedMilliseconds} мс',
    );
  } on TimeoutException {
    stopwatch.stop();
    return LlmConnectionResult(
      ok: false,
      elapsedMs: stopwatch.elapsedMilliseconds,
      message: 'API не ответил за 30 секунд. Проверь интернет или VPN.',
    );
  } on FormatException catch (error) {
    stopwatch.stop();
    return LlmConnectionResult(
      ok: false,
      elapsedMs: stopwatch.elapsedMilliseconds,
      message: error.message,
    );
  } catch (error) {
    stopwatch.stop();
    return LlmConnectionResult(
      ok: false,
      elapsedMs: stopwatch.elapsedMilliseconds,
      message: 'Не удалось подключиться: $error',
    );
  } finally {
    if (ownClient) httpClient.close();
  }
}
