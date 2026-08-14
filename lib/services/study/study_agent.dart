import '../agent/agent_loop.dart';
import '../agent/agent_policy.dart';
import '../agent/hermes_tool_registry.dart';
import '../agent/tool_definition.dart';
import 'study_skill_router.dart';

/// Study-specific entry point for Hermes.
///
/// The caller does not need to manually select a prompt mode. The router turns
/// the user's request into a bounded Study skill and injects its contract into
/// the same agent loop used by the rest of Hermes.
Future<AgentResult> runStudyAgentLoop({
  required String userMessage,
  required String apiUrl,
  required String apiKey,
  required String model,
  required String systemPrompt,
  required List<Map<String, dynamic>> history,
  required Future<String> Function(AgentToolCall call) executeTool,
  String? subject,
  String? paragraphId,
  AgentToolPolicy policy = const AgentToolPolicy(),
  Future<bool> Function(AgentToolCall call)? confirmTool,
  int maxRounds = 8,
  int maxTokens = 1600,
}) {
  final request = studySkillRouter.route(
    message: userMessage,
    subject: subject,
    paragraphId: paragraphId,
  );
  final skillContext = studySkillRouter.systemContext(request);

  return runAgentLoop(
    apiUrl: apiUrl,
    apiKey: apiKey,
    model: model,
    systemPrompt: systemPrompt,
    history: history,
    tools: hermesToolRegistry.definitions,
    executeTool: executeTool,
    policy: policy,
    registry: hermesToolRegistry,
    confirmTool: confirmTool,
    skillContext: skillContext,
    maxRounds: maxRounds,
    maxTokens: maxTokens,
    temperature: 0.35,
  );
}

/// Convenience helper for code that already builds its own tool list. The
/// registry remains the authority and strips anything not registered.
List<ToolDefinition> studyTools() => hermesToolRegistry.definitions;
