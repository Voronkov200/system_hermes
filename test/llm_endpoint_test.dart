import 'package:flutter_test/flutter_test.dart';
import 'package:system_hermes/services/llm_endpoint.dart';

void main() {
  group('openAiChatCompletionsUri', () {
    test('добавляет endpoint к Base URL B.ai', () {
      expect(
        openAiChatCompletionsUri('https://api.b.ai/v1').toString(),
        'https://api.b.ai/v1/chat/completions',
      );
    });

    test('добавляет v1 к URL без версии', () {
      expect(
        openAiChatCompletionsUri('https://api.b.ai/').toString(),
        'https://api.b.ai/v1/chat/completions',
      );
    });

    test('сохраняет полный endpoint старого провайдера', () {
      const endpoint =
          'https://api.groq.com/openai/v1/chat/completions';
      expect(openAiChatCompletionsUri(endpoint).toString(), endpoint);
    });

    test('отклоняет некорректный URL', () {
      expect(
        () => openAiChatCompletionsUri('api.b.ai/v1'),
        throwsFormatException,
      );
    });
  });
}
