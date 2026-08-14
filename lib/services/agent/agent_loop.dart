// Агентный цикл: LLM + инструменты (function calling).
// Перед каждым вызовом применяется детерминированная AgentToolPolicy.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'agent_policy.dart';
import 'hermes_tool_registry.dart';
import 'tool_definition.dart';

class AgentToolCall extends AgentPolicyCall {
  const AgentToolCall(super.name, super.arguments);
}

class AgentStep {
  final String toolName;
  final String result;
  const AgentStep(this.toolName, this.result);
}

class AgentResult {
  final String content;
  final List<AgentStep> steps;
  const AgentResult({required this.content, required this.steps});
}

Future<AgentResult> runAgentLoop({
  required String apiUrl,
  required String apiKey,
  required String model,
  required String systemPrompt,
  required List<Map<String, dynamic>> history,
  required List<ToolDefinition> tools,
  required Future<String> Function(AgentToolCall call) executeTool,
  AgentToolPolicy policy = const AgentToolPolicy(),
  HermesToolRegistry registry = hermesToolRegistry,
  Future<bool> Function(AgentToolCall call)? confirmTool,
  String? skillContext,
  int maxRounds = 6,
  int maxTokens = 1200,
  double temperature = 0.7,
  int timeoutSeconds = 90,
}) async {
  final registeredTools = registry.sanitize(tools);
  final effectivePrompt = skillContext == null || skillContext.trim().isEmpty
      ? systemPrompt
      : '$systemPrompt\n\n$skillContext';
  final messages = <Map<String, dynamic>>[
    {'role': 'system', 'content': effectivePrompt},
    ...history,
  ];
  final steps = <AgentStep>[];
  var lastContent = '';

  for (var round = 0; round < maxRounds; round++) {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'tools': registeredTools.map((t) => t.toJson()).toList(),
              'temperature': temperature,
              'max_tokens': maxTokens,
            }),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    } on Exception catch (e) {
      throw Exception('Не удалось связаться с сервером ИИ: $e');
    }

    if (res.statusCode != 200) {
      final reason = switch (res.statusCode) {
        401 => 'неверный API-ключ (401)',
        404 => 'неверный URL или модель (404)',
        429 => 'превышен лимит запросов (429)',
        _ => 'ошибка сервера ИИ (HTTP ${res.statusCode})',
      };
      throw Exception(reason);
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Некорректный ответ сервера ИИ');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) throw Exception('Пустой ответ API');
    final first = choices.first;
    if (first is! Map || first['message'] is! Map) {
      throw Exception('Некорректный ответ сервера ИИ');
    }
    final message = (first['message'] as Map).cast<String, dynamic>();
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      lastContent = content.trim();
    }
    messages.add(message);

    final rawCalls = message['tool_calls'];
    if (rawCalls is! List || rawCalls.isEmpty) break;

    for (final raw in rawCalls) {
      if (raw is! Map) continue;
      final fnRaw = raw['function'];
      final fn = fnRaw is Map
          ? fnRaw.cast<String, dynamic>()
          : const <String, dynamic>{};
      final name = fn['name'];
      if (name is! String || name.isEmpty) continue;

      Map<String, dynamic> args = {};
      final rawArgs = fn['arguments'];
      if (rawArgs is String) {
        try {
          final decoded = jsonDecode(rawArgs);
          if (decoded is Map) args = decoded.cast<String, dynamic>();
        } catch (_) {
          // Empty args are deliberately left for policy/executor validation.
        }
      }

      final callId = raw['id'] is String ? raw['id'] as String : '';
      final call = AgentToolCall(name, args);
      final decision = policy.decide(call);
      String result;

      if (decision == ToolDecision.deny || !registry.contains(name)) {
        result = 'Инструмент заблокирован политикой безопасности: $name';
      } else if (decision == ToolDecision.confirm) {
        final approved = confirmTool == null ? false : await confirmTool(call);
        result = approved
            ? await _executeSafely(executeTool, call)
            : 'Действие требует подтверждения пользователя и не выполнено: $name';
      } else {
        result = await _executeSafely(executeTool, call);
      }

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

Future<String> _executeSafely(
  Future<String> Function(AgentToolCall call) executeTool,
  AgentToolCall call,
) async {
  try {
    return await executeTool(call);
  } catch (e) {
    return 'Ошибка инструмента: $e';
  }
}
