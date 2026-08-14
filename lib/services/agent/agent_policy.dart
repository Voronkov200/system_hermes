/// Risk level for an agent tool.
enum ToolRisk { read, write, destructive, sensitive }

/// Policy decision returned before a tool is executed.
enum ToolDecision { allow, deny, confirm }

/// Minimal shape needed by the policy. Kept here to avoid a dependency cycle
/// between the policy and the agent loop.
class AgentPolicyCall {
  final String name;
  final Map<String, dynamic> arguments;

  const AgentPolicyCall(this.name, this.arguments);
}

/// Central deterministic policy for Hermes tools. Unknown tools fail closed.
class AgentToolPolicy {
  const AgentToolPolicy();

  ToolDecision decide(AgentPolicyCall call) {
    if (!_known.contains(call.name)) return ToolDecision.deny;
    final risk = riskFor(call.name);
    switch (risk) {
      case ToolRisk.read:
        return ToolDecision.allow;
      case ToolRisk.write:
        return _isSafeWrite(call) ? ToolDecision.allow : ToolDecision.confirm;
      case ToolRisk.destructive:
      case ToolRisk.sensitive:
        return ToolDecision.confirm;
    }
  }

  ToolRisk riskFor(String toolName) {
    if (_destructive.contains(toolName)) return ToolRisk.destructive;
    if (_sensitive.contains(toolName)) return ToolRisk.sensitive;
    if (_write.contains(toolName)) return ToolRisk.write;
    return ToolRisk.read;
  }

  bool _isSafeWrite(AgentPolicyCall call) {
    if (call.name == 'set_task' || call.name == 'journal_add' ||
        call.name == 'create_obsidian_note') {
      return true;
    }
    final path = call.arguments['path'] ?? call.arguments['outPath'];
    if (path is! String || path.trim().isEmpty) return false;
    final normalized = path.replaceAll('\\', '/').trim();
    if (normalized.startsWith('/') || normalized.contains('..')) return false;
    return normalized.startsWith('SystemHermes/') ||
        normalized.startsWith('study/') ||
        normalized.startsWith('notes/') ||
        normalized.startsWith('docs/');
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

  static const _read = {
    'web_search',
    'get_webpage',
    'search_knowledge',
    'read_obsidian_note',
    'read_pdf',
    'read_file',
    'list_dir',
    'get_currency_rates',
    'list_tasks',
    'mark_task_done',
  };

  static const _known = {
    ..._read,
    ..._write,
    ..._destructive,
    ..._sensitive,
  };
}
