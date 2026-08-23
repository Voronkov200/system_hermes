/// Преобразует Base URL OpenAI-совместимого провайдера в конечную точку
/// chat/completions. Полные endpoint-URL старых настроек остаются рабочими.
Uri openAiChatCompletionsUri(String configuredUrl) {
  final raw = configuredUrl.trim();
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const FormatException('Некорректный Base URL модели Hermes');
  }

  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  final alreadyComplete = segments.length >= 2 &&
      segments[segments.length - 2] == 'chat' &&
      segments.last == 'completions';
  if (alreadyComplete) return uri;

  if (segments.isEmpty || segments.last != 'v1') {
    segments.add('v1');
  }
  segments
    ..add('chat')
    ..add('completions');
  return uri.replace(pathSegments: segments);
}
