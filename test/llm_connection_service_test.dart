import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_hermes/services/llm_connection_service.dart';
import 'package:system_hermes/services/settings_service.dart';

void main() {
  test('connection check sends a minimal B.ai request', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.b.ai/v1/chat/completions');
      expect(request.headers['authorization'], 'Bearer test-key');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'deepseek-v4-flash');
      expect(body['tools'], isNull);
      return http.Response(
        '{"choices":[{"message":{"content":"OK"}}]}',
        200,
      );
    });

    final result = await testHermesLlmConnection(
      SettingsState(hermesLlmApiKey: 'Bearer test-key'),
      client: client,
    );

    expect(result.ok, isTrue);
    expect(result.message, contains('Подключено'));
  });

  test('connection check exposes a useful API error', () async {
    final client = MockClient((_) async => http.Response(
          '{"error":{"message":"model is unavailable"}}',
          404,
        ));

    final result = await testHermesLlmConnection(
      SettingsState(hermesLlmApiKey: 'test-key'),
      client: client,
    );

    expect(result.ok, isFalse);
    expect(result.statusCode, 404);
    expect(result.message, contains('model is unavailable'));
  });
}
