import 'agent_loop.dart';

/// Risk level for an agent tool.
enum ToolRisk { read, write, destructive, sensitive }

/// Policy decision returned before a tool is executed.
enum ToolDecision { allow, deny, confirm }

/// Central policy for Hermes tools. Keep this deterministic: the LLM never
/// decides its own permissions.
class AgentToolPolicy {
  const AgentToolPolicy();

  ToolRisk riskFor(String toolName) {
    if (_destructive.contains(toolName)) return ToolRisk.destructive;
    if (_sensitive.contains(toolName)) return ToolRisk.sensitive;
    if (_write.contains(toolName)) return ToolRisk.write;
    return ToolRisk.read;
  }

  ToolDecision decide(AgentToolCall call) {
    final risk = riskFor(call.name);
    switch (risk) {
      case ToolRisk.read:
        return ToolDecision.allow;
      case ToolRisk.write:
        return _isSafeWrite(call) ? ToolDecision.allow : ToolDecision.confirm;
      case ToolRisk.destructive:
        return ToolDecision.confirm;
      case ToolRisk.sensitive:
        return ToolDecision.confirm;
    }
  }

  bool _isSafeWrite(AgentToolCall call) {
    final path = call.arguments['path'];
    if (path is! String || path.trim().isEmpty) return false;
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.contains('../')) return false;
    return normalized.startsWith('SystemHermes/') ||
        normalized.startsWith('study/') ||
        normalized.startsWith('notes/');
  }

  static const _write = {
    'write_file',
    'create_obsidian_note',
    'set_task',
    'journal_add',
    'make_pdf',
    'make_study_pdf',
  };

  static const _destructive = {
    'delete_file',
    'delete_obsidian_note',
    'clear_study_data',
    'reset_progress',
  };

  static const _sensitive = {
    'update_dopamine_protocol_status',
    'request_photo_verification',
    'get_health_data',
    'get_github_commits',
  };
}
