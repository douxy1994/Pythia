import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pythia_windows/core/translation_service.dart';
import 'package:pythia_windows/platform/credential_store.dart';

void main() {
  test('OpenAI-compatible provider reads API key from credential store',
      () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    Map<String, Object?>? requestedBody;

    final provider = OpenAICompatibleTranslationProvider(
      id: 'openai-compatible',
      displayName: 'Test Provider',
      baseUrl: 'https://example.com/v1/',
      model: 'test-model',
      credentialStore: MemoryCredentialStore({
        'provider.openai-compatible.apiKey': 'test-secret',
      }),
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        requestedHeaders = request.headers;
        requestedBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '你好'}
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await provider.translate(const PythiaTranslationRequest(
      text: 'hello',
      sourceLanguage: 'auto',
      targetLanguage: 'zh-CN',
      serviceId: 'openai-compatible',
    ));

    expect(result.text, '你好');
    expect(result.model, 'test-model');
    expect(requestedUri, Uri.parse('https://example.com/v1/chat/completions'));
    expect(requestedHeaders?['Authorization'], 'Bearer test-secret');
    expect(requestedBody?['model'], 'test-model');
  });

  test('mixed Chinese and English source follows selected English target',
      () async {
    final languages = TranslationServiceRegistry.resolvedLanguages(
      text: '今天 weather 很好',
      sourceLanguage: 'auto',
      targetLanguage: 'en',
    );

    expect(languages.source, 'zh-CN');
    expect(languages.target, 'en');
  });

  test('pure Chinese auto source defaults to English target', () async {
    final languages = TranslationServiceRegistry.resolvedLanguages(
      text: '今天天气很好',
      sourceLanguage: 'auto',
      targetLanguage: 'zh-CN',
    );

    expect(languages.source, 'auto');
    expect(languages.target, 'en');
  });

  test('pure English auto source defaults to Chinese target', () async {
    final languages = TranslationServiceRegistry.resolvedLanguages(
      text: 'The weather is good today.',
      sourceLanguage: 'auto',
      targetLanguage: 'en',
    );

    expect(languages.source, 'auto');
    expect(languages.target, 'zh-CN');
  });

  test('mixed Chinese and English source follows selected Chinese target',
      () async {
    final languages = TranslationServiceRegistry.resolvedLanguages(
      text: '今天 weather 很好',
      sourceLanguage: 'auto',
      targetLanguage: 'zh-CN',
    );

    expect(languages.source, 'en');
    expect(languages.target, 'zh-CN');
  });

  test('registry passes effective mixed-language pair to providers', () async {
    Map<String, Object?>? requestedBody;
    final provider = OpenAICompatibleTranslationProvider(
      id: 'openai-compatible',
      displayName: 'Test Provider',
      baseUrl: 'https://example.com/v1',
      model: 'test-model',
      credentialStore: MemoryCredentialStore({
        'provider.openai-compatible.apiKey': 'test-secret',
      }),
      httpClient: MockClient((request) async {
        requestedBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'The weather is good today.'}
              }
            ],
          }),
          200,
        );
      }),
    );
    final registry = TranslationServiceRegistry([provider]);

    await registry.translateAll(
      text: '今天 weather 很好',
      sourceLanguage: 'auto',
      targetLanguage: 'en',
      serviceIds: const ['openai-compatible'],
    );

    final messages = requestedBody?['messages'] as List<Object?>;
    final system = messages.first as Map<String, Object?>;
    expect(system['content'], contains('from zh-CN to en'));
  });

  test('OpenAI-compatible provider reports missing API key', () async {
    final provider = OpenAICompatibleTranslationProvider(
      id: 'openai-compatible',
      displayName: 'Test Provider',
      baseUrl: 'https://example.com/v1',
      model: 'test-model',
      credentialStore: MemoryCredentialStore(<String, String>{}),
      httpClient: MockClient((request) async => http.Response('{}', 500)),
    );

    expect(
      provider.translate(const PythiaTranslationRequest(
        text: 'hello',
        sourceLanguage: 'auto',
        targetLanguage: 'zh-CN',
        serviceId: 'openai-compatible',
      )),
      throwsA(isA<StateError>()),
    );
  });

  test('DeepL provider uses Credential Store and maps Chinese target',
      () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    Map<String, String>? requestedForm;
    final provider = DeepLTranslationProvider(
      baseUrl: 'https://api-free.deepl.com/v2/',
      credentialStore: MemoryCredentialStore({
        'provider.deepl.apiKey': 'deepl-secret',
      }),
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        requestedHeaders = request.headers;
        requestedForm = Uri.splitQueryString(request.body);
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'translations': [
              {'text': '你好', 'detected_source_language': 'EN'}
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await provider.translate(const PythiaTranslationRequest(
      text: 'hello',
      sourceLanguage: 'auto',
      targetLanguage: 'zh-CN',
      serviceId: 'deepl',
    ));

    expect(result.text, '你好');
    expect(requestedUri, Uri.parse('https://api-free.deepl.com/v2/translate'));
    expect(requestedHeaders?['Authorization'], 'DeepL-Auth-Key deepl-secret');
    expect(requestedForm?['text'], 'hello');
    expect(requestedForm?['target_lang'], 'ZH-HANS');
    expect(requestedForm?.containsKey('source_lang'), isFalse);
  });

  test('DeepL provider reports missing API key', () async {
    final provider = DeepLTranslationProvider(
      baseUrl: 'https://api-free.deepl.com/v2',
      credentialStore: MemoryCredentialStore({}),
      httpClient: MockClient((_) async => http.Response('{}', 500)),
    );

    expect(
      provider.translate(const PythiaTranslationRequest(
        text: 'hello',
        sourceLanguage: 'auto',
        targetLanguage: 'zh-CN',
        serviceId: 'deepl',
      )),
      throwsA(isA<StateError>()),
    );
  });

  test('LibreTranslate provider sends JSON and optional API key', () async {
    Uri? requestedUri;
    Map<String, Object?>? requestedBody;
    final provider = LibreTranslateTranslationProvider(
      baseUrl: 'https://libre.example/',
      credentialStore: MemoryCredentialStore({
        'provider.libretranslate.apiKey': 'libre-secret',
      }),
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        requestedBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({'translatedText': 'Hello world'}),
          200,
        );
      }),
    );

    final result = await provider.translate(const PythiaTranslationRequest(
      text: '你好世界',
      sourceLanguage: 'zh-CN',
      targetLanguage: 'en',
      serviceId: 'libretranslate',
    ));

    expect(result.text, 'Hello world');
    expect(requestedUri, Uri.parse('https://libre.example/translate'));
    expect(requestedBody, {
      'q': '你好世界',
      'source': 'zh',
      'target': 'en',
      'format': 'text',
      'api_key': 'libre-secret',
    });
  });

  test('Google provider maps language query and joins sentence results',
      () async {
    Uri? requestedUri;
    final provider = GoogleTranslationProvider(
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(jsonEncode([
            [
              ['你好', 'hello'],
              ['世界', ' world'],
            ]
          ])),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await provider.translate(const PythiaTranslationRequest(
      text: 'hello world',
      sourceLanguage: 'auto',
      targetLanguage: 'zh-CN',
      serviceId: 'google',
    ));

    expect(result.text, '你好世界');
    expect(requestedUri?.queryParameters['client'], 'gtx');
    expect(requestedUri?.queryParameters['sl'], 'auto');
    expect(requestedUri?.queryParameters['tl'], 'zh-CN');
    expect(requestedUri?.queryParameters['q'], 'hello world');
  });

  test('Baidu provider signs request with Credential Manager secrets',
      () async {
    Uri? requestedUri;
    final provider = BaiduTranslationProvider(
      credentialStore: MemoryCredentialStore({
        'provider.baidu.appId': 'app-id',
        'provider.baidu.secret': 'baidu-secret',
      }),
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'trans_result': [
              {'dst': '你好'}
            ]
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      saltFactory: () => '12345',
    );

    final result = await provider.translate(const PythiaTranslationRequest(
      text: 'hello',
      sourceLanguage: 'en',
      targetLanguage: 'zh-CN',
      serviceId: 'baidu',
    ));
    final expectedSign = md5
        .convert(
          utf8.encode('app-id' 'hello' '12345' 'baidu-secret'),
        )
        .toString();

    expect(result.text, '你好');
    expect(requestedUri?.queryParameters['from'], 'en');
    expect(requestedUri?.queryParameters['to'], 'zh');
    expect(requestedUri?.queryParameters['appid'], 'app-id');
    expect(requestedUri?.queryParameters['sign'], expectedSign);
  });

  test('Youdao provider uses v3 SHA-256 signing and language mapping',
      () async {
    Uri? requestedUri;
    const sourceText = '1234567890abcdefghij12345';
    final provider = YoudaoTranslationProvider(
      credentialStore: MemoryCredentialStore({
        'provider.youdao.appKey': 'youdao-key',
        'provider.youdao.secret': 'youdao-secret',
      }),
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'errorCode': '0',
            'translation': ['测试结果'],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      saltFactory: () => 'fixed-salt',
      epochSeconds: () => 1700000000,
    );

    final result = await provider.translate(const PythiaTranslationRequest(
      text: sourceText,
      sourceLanguage: 'auto',
      targetLanguage: 'zh-CN',
      serviceId: 'youdao',
    ));
    final input = '1234567890${sourceText.length}fghij12345';
    final expectedSign = sha256
        .convert(
          utf8.encode(
            'youdao-key$input' 'fixed-salt' '1700000000' 'youdao-secret',
          ),
        )
        .toString();

    expect(result.text, '测试结果');
    expect(requestedUri?.queryParameters['signType'], 'v3');
    expect(requestedUri?.queryParameters['to'], 'zh-CHS');
    expect(requestedUri?.queryParameters['sign'], expectedSign);
  });
}

class MemoryCredentialStore implements CredentialStore {
  final Map<String, String> values;

  MemoryCredentialStore(this.values);

  @override
  Future<void> deleteSecret(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> readSecret(String key) async => values[key];

  @override
  Future<void> writeSecret(String key, String value) async {
    values[key] = value;
  }
}
