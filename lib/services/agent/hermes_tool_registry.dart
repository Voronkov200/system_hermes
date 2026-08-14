import 'tool_definition.dart';

/// Single source of truth for the tools exposed to Hermes.
///
/// The executor still owns the implementation; this registry owns the public
/// contract, validation and the set sent to the model. Unknown tools are never
/// exposed by the registry.
class HermesToolRegistry {
  const HermesToolRegistry();

  List<ToolDefinition> get definitions => const [
        ToolDefinition(name: 'web_search', description: 'Search the web for current information.'),
        ToolDefinition(name: 'get_webpage', description: 'Read a web page by URL.'),
        ToolDefinition(name: 'search_knowledge', description: 'Search the local knowledge base.'),
        ToolDefinition(name: 'read_obsidian_note', description: 'Read an Obsidian note.'),
        ToolDefinition(name: 'read_pdf', description: 'Read selected pages from a PDF.'),
        ToolDefinition(name: 'read_file', description: 'Read a local file in the allowed workspace.'),
        ToolDefinition(name: 'list_dir', description: 'List files in the allowed workspace directory.'),
        ToolDefinition(name: 'get_currency_rates', description: 'Get current currency rates.'),
        ToolDefinition(name: 'list_tasks', description: 'List current tasks.'),
        ToolDefinition(name: 'mark_task_done', description: 'Mark a task as completed.'),
        ToolDefinition(name: 'write_file', description: 'Write a file in the allowed workspace.'),
        ToolDefinition(name: 'create_obsidian_note', description: 'Create an Obsidian note.'),
        ToolDefinition(name: 'set_task', description: 'Create or update a task.'),
        ToolDefinition(name: 'journal_add', description: 'Append an entry to the journal.'),
        ToolDefinition(name: 'make_pdf', description: 'Create a PDF from generated content.'),
        ToolDefinition(name: 'make_study_pdf', description: 'Create a study summary PDF.'),
        ToolDefinition(name: 'delete_file', description: 'Delete a local file after confirmation.'),
        ToolDefinition(name: 'delete_obsidian_note', description: 'Delete an Obsidian note after confirmation.'),
        ToolDefinition(name: 'clear_study_data', description: 'Clear study data after confirmation.'),
        ToolDefinition(name: 'reset_progress', description: 'Reset learning progress after confirmation.'),
        ToolDefinition(name: 'update_dopamine_protocol_status', description: 'Update protocol status after confirmation.'),
        ToolDefinition(name: 'request_photo_verification', description: 'Request a photo verification action after confirmation.'),
        ToolDefinition(name: 'get_health_data', description: 'Read health data after confirmation.'),
        ToolDefinition(name: 'get_github_commits', description: 'Read GitHub commit information after confirmation.'),
      ];

  bool contains(String name) => definitions.any((tool) => tool.name == name);

  ToolDefinition? find(String name) {
    for (final tool in definitions) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  /// Drops tool definitions that are not registered. This protects against a
  /// caller accidentally exposing an ad-hoc function to the LLM.
  List<ToolDefinition> sanitize(Iterable<ToolDefinition> requested) =>
      requested.where((tool) => contains(tool.name)).toList(growable: false);
}

const hermesToolRegistry = HermesToolRegistry();
