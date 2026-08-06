// Агентный цикл: LLM + инструменты (function calling).
//
// Работает с любым OpenAI-совместимым API (Groq, OpenCode Zen, OpenRouter):
// запрос уходит с описанием инструментов, LLM решает, какие инструменты
// вызвать, мы их выполняем локально и возвращаем результат — и так по
// кругу, пока LLM не даст финальный ответ (или не упрёмся в лимит ходов).

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Описание инструмента для LLM (OpenAI function calling).
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ToolDefinition({
    required this.name,
    required this.description,
    this.parameters = const {'type': 'object', 'properties': {}},
  });

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// Вызов инструмента, который попросила LLM.
class AgentToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const AgentToolCall(this.name, this.arguments);
}

/// Один выполненный инструмент.
class AgentStep {
  final String toolName;
  final String result;

  const AgentStep(this.toolName, this.result);
}

/// Итог работы агента: финальный ответ + журнал инструментов.
class AgentResult {
  final String content;
  final List<AgentStep> steps;

  const AgentResult({required this.content, required this.steps});
}

/// Запуск агентного цикла.
Future<AgentResult> runAgentLoop({
  required String apiUrl,
  required String apiKey,
  required String model,
  required String systemPrompt,
  required List<Map<String, dynamic>> history,
  required List<ToolDefinition> tools,
  required Future<String> Function(AgentToolCall call) executeTool,
  int maxRounds = 6,
  int maxTokens = 1200,
  double temperature = 0.7,
  int timeoutSeconds = 90,
}) async {
  final messages = <Map<String, dynamic>>[
    {'role': 'system', 'content': systemPrompt},
    ...history,
  ];
  final steps = <AgentStep>[];
  var lastContent = '';

  for (var round = 0; round < maxRounds; round++) {
    final res = await http
        .post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'tools': tools.map((t) => t.toJson()).toList(),
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
      throw Exception(reason);
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List? ?? const [];
    if (choices.isEmpty) throw Exception('Пустой ответ API');
    final message = (choices.first as Map)['message'] as Map<String, dynamic>;
    final content = message['content'] as String? ?? '';
    if (content.trim().isNotEmpty) lastContent = content.trim();
    messages.add(message);

    final rawCalls = message['tool_calls'] as List? ?? const [];
    if (rawCalls.isEmpty) break;

    for (final raw in rawCalls) {
      if (raw is! Map) continue;
      final fn = (raw['function'] as Map?) ?? const <String, dynamic>{};
      final name = (fn['name'] as String?) ?? '';
      if (name.isEmpty) continue;
      final rawArgs = (fn['arguments'] as String?) ?? '{}';
      Map<String, dynamic> args = {};
      try {
        args = (jsonDecode(rawArgs) as Map).cast<String, dynamic>();
      } catch (_) {}
      final callId = (raw['id'] as String?) ?? '';
      final result = await executeTool(AgentToolCall(name, args));
      steps.add(AgentStep(name, result));
      messages.add({
        'role': 'tool',
        'tool_call_id': callId,
        'content': result,
      });
    }
  }

  return AgentResult(content: lastContent, steps: steps);
}
