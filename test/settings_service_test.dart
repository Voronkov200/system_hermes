import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_hermes/core/constants.dart';
import 'package:system_hermes/services/settings_service.dart';

void main() {
  Future<SettingsState> readSettings(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container.read(settingsProvider);
  }

  test('новая установка использует B.ai Flash', () async {
    final settings = await readSettings({});
    expect(settings.hermesLlmUrl, 'https://api.b.ai/v1');
    expect(settings.hermesLlmModel, 'deepseek-v4-flash');
    expect(settings.whisperApiKey, isEmpty);
  });

  test('нетронутый Groq без ключа переводится на B.ai', () async {
    final settings = await readSettings({
      PrefKeys.hermesLlmUrl:
          'https://api.groq.com/openai/v1/chat/completions',
      PrefKeys.hermesLlmModel: 'llama-3.3-70b-versatile',
      PrefKeys.hermesLlmApiKey: '',
    });
    expect(settings.hermesLlmUrl, AppConstants.hermesLlmDefaultUrl);
    expect(settings.hermesLlmModel, AppConstants.hermesLlmDefaultModel);
  });

  test('пользовательский провайдер и ключ сохраняются', () async {
    final settings = await readSettings({
      PrefKeys.hermesLlmUrl: 'https://example.test/v1',
      PrefKeys.hermesLlmModel: 'custom-model',
      PrefKeys.hermesLlmApiKey: 'private-test-key',
    });
    expect(settings.hermesLlmUrl, 'https://example.test/v1');
    expect(settings.hermesLlmModel, 'custom-model');
    expect(settings.hermesLlmApiKey, 'private-test-key');
  });
}
