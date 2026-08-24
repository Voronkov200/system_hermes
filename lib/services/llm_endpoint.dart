import 'dart:convert';

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

/// Пользователи нередко копируют ключ вместе с префиксом из примера curl.
/// В заголовке приложения Bearer добавляется самостоятельно, поэтому здесь
/// безопасно убираем только один ведущий префикс.
String normalizeApiKey(String value) {
  final key = value.trim();
  if (key.toLowerCase().startsWith('bearer ')) {
    return key.substring(7).trim();
  }
  return key;
}

/// Извлекает короткую безопасную причину из OpenAI-совместимого ответа.
/// API-ключ в тело ответа не отправляется, а слишком длинный HTML обрезается.
String llmApiErrorMessage(int statusCode, String responseBody) {
  String? detail;
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        detail = error['message'] as String;
      } else if (decoded['message'] is String) {
        detail = decoded['message'] as String;
      } else if (decoded['detail'] is String) {
        detail = decoded['detail'] as String;
      }
    }
  } catch (_) {
    // Некоторые прокси отвечают текстом или HTML — ниже используем только
    // короткое читаемое тело, если оно не похоже на страницу.
    final plain = responseBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (plain.isNotEmpty && !plain.toLowerCase().contains('<html')) {
      detail = plain;
    }
  }

  if (detail != null) {
    detail = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (detail.length > 180) detail = '${detail.substring(0, 180)}…';
  }

  final base = switch (statusCode) {
    400 => 'Запрос отклонён: проверь модель и Base URL (400)',
    401 => 'API-ключ неверный или отозван (401)',
    402 => 'На аккаунте провайдера нет доступного баланса (402)',
    403 => 'У ключа нет доступа к выбранной модели (403)',
    404 => 'Не найден URL или модель (404)',
    408 => 'Провайдер не дождался выполнения запроса (408)',
    429 => 'Лимит запросов исчерпан — попробуй позже (429)',
    >= 500 => 'Сервис ИИ временно недоступен (HTTP $statusCode)',
    _ => 'Ошибка API (HTTP $statusCode)',
  };
  return detail == null || detail.isEmpty ? base : '$base: $detail';
}
