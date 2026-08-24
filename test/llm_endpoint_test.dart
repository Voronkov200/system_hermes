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

  group('API key and errors', () {
    test('removes accidental Bearer prefix', () {
      expect(normalizeApiKey('  Bearer secret-key  '), 'secret-key');
      expect(normalizeApiKey('secret-key'), 'secret-key');
    });

    test('shows provider error detail without dumping JSON', () {
      expect(
        llmApiErrorMessage(
          401,
          '{"error":{"message":"Invalid API key"}}',
        ),
        contains('Invalid API key'),
      );
      expect(llmApiErrorMessage(429, ''), contains('Лимит запросов'));
    });
  });
}
