import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../platform/credential_store.dart';

class PythiaTranslationRequest {
  final String text;
  final String sourceLanguage;
  final String targetLanguage;
  final String serviceId;

  const PythiaTranslationRequest({
    required this.text,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.serviceId,
  });
}

class PythiaTranslationResult {
  final String serviceId;
  final String serviceName;
  final String text;
  final String? model;

  const PythiaTranslationResult({
    required this.serviceId,
    required this.serviceName,
    required this.text,
    this.model,
  });
}

class PythiaLanguagePair {
  final String source;
  final String target;

  const PythiaLanguagePair({
    required this.source,
    required this.target,
  });
}

abstract interface class TranslationProvider {
  String get id;
  String get displayName;

  Future<PythiaTranslationResult> translate(PythiaTranslationRequest request);
}

class LocalEchoTranslationProvider implements TranslationProvider {
  @override
  String get id => 'local';

  @override
  String get displayName => 'Local';

  @override
  Future<PythiaTranslationResult> translate(PythiaTranslationRequest request) {
    return Future.value(PythiaTranslationResult(
      serviceId: id,
      serviceName: displayName,
      text: request.text,
    ));
  }
}

class GoogleTranslationProvider implements TranslationProvider {
  @override
  String get id => 'google';

  @override
  String get displayName => 'Google';

  final http.Client httpClient;

  const GoogleTranslationProvider({required this.httpClient});

  @override
  Future<PythiaTranslationResult> translate(
      PythiaTranslationRequest request) async {
    final uri = Uri.https(
      'translate.googleapis.com',
      '/translate_a/single',
      {
        'client': 'gtx',
        'sl': request.sourceLanguage.isEmpty ? 'auto' : request.sourceLanguage,
        'tl': request.targetLanguage.isEmpty ? 'zh-CN' : request.targetLanguage,
        'dt': 't',
        'q': request.text,
      },
    );
    final response =
        await httpClient.get(uri).timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$displayName HTTP ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as List<Object?>;
    final sentences = payload.firstOrNull as List<Object?>? ?? const [];
    final translated = sentences
        .whereType<List<Object?>>()
        .map((sentence) => sentence.firstOrNull)
        .whereType<String>()
        .join();
    if (translated.trim().isEmpty) throw StateError('$displayName 返回空译文');
    return PythiaTranslationResult(
      serviceId: id,
      serviceName: displayName,
      text: translated.trim(),
    );
  }
}

class BaiduTranslationProvider implements TranslationProvider {
  @override
  String get id => 'baidu';

  @override
  String get displayName => '百度翻译';

  final CredentialStore credentialStore;
  final http.Client httpClient;
  final String Function() saltFactory;

  BaiduTranslationProvider({
    required this.credentialStore,
    required this.httpClient,
    String Function()? saltFactory,
  }) : saltFactory = saltFactory ?? _defaultBaiduSalt;

  @override
  Future<PythiaTranslationResult> translate(
      PythiaTranslationRequest request) async {
    final appId = await credentialStore.readSecret('provider.baidu.appId');
    final secret = await credentialStore.readSecret('provider.baidu.secret');
    if (appId == null || appId.isEmpty || secret == null || secret.isEmpty) {
      throw StateError('$displayName 缺少 AppID 或密钥');
    }
    final salt = saltFactory();
    final sign = md5
        .convert(utf8.encode('$appId${request.text}$salt$secret'))
        .toString();
    final uri = Uri.https(
      'fanyi-api.baidu.com',
      '/api/trans/vip/translate',
      {
        'q': request.text,
        'from': _baiduLanguage(request.sourceLanguage),
        'to': _baiduLanguage(request.targetLanguage),
        'appid': appId,
        'salt': salt,
        'sign': sign,
      },
    );
    final response =
        await httpClient.get(uri).timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$displayName HTTP ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final error = payload['error_msg'] as String?;
    if (error != null && error.isNotEmpty) {
      throw StateError('$displayName：$error');
    }
    final translated = (payload['trans_result'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .map((item) => item['dst'])
        .whereType<String>()
        .join('\n');
    if (translated.trim().isEmpty) throw StateError('$displayName 返回空译文');
    return PythiaTranslationResult(
      serviceId: id,
      serviceName: displayName,
      text: translated.trim(),
    );
  }

  static String _defaultBaiduSalt() =>
      DateTime.now().millisecondsSinceEpoch.toString();
}

class YoudaoTranslationProvider implements TranslationProvider {
  @override
  String get id => 'youdao';

  @override
  String get displayName => '有道翻译';

  final CredentialStore credentialStore;
  final http.Client httpClient;
  final String Function() saltFactory;
  final int Function() epochSeconds;

  YoudaoTranslationProvider({
    required this.credentialStore,
    required this.httpClient,
    String Function()? saltFactory,
    int Function()? epochSeconds,
  })  : saltFactory = saltFactory ?? _defaultYoudaoSalt,
        epochSeconds = epochSeconds ?? _defaultEpochSeconds;

  @override
  Future<PythiaTranslationResult> translate(
      PythiaTranslationRequest request) async {
    final appKey = await credentialStore.readSecret('provider.youdao.appKey');
    final secret = await credentialStore.readSecret('provider.youdao.secret');
    if (appKey == null || appKey.isEmpty || secret == null || secret.isEmpty) {
      throw StateError('$displayName 缺少 AppKey 或密钥');
    }
    final salt = saltFactory();
    final currentTime = epochSeconds().toString();
    final input = _truncateForYoudao(request.text);
    final sign = sha256
        .convert(utf8.encode('$appKey$input$salt$currentTime$secret'))
        .toString();
    final uri = Uri.https('openapi.youdao.com', '/api', {
      'q': request.text,
      'from': _youdaoLanguage(request.sourceLanguage, source: true),
      'to': _youdaoLanguage(request.targetLanguage, source: false),
      'appKey': appKey,
      'salt': salt,
      'sign': sign,
      'signType': 'v3',
      'curtime': currentTime,
    });
    final response =
        await httpClient.get(uri).timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$displayName HTTP ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final errorCode = payload['errorCode']?.toString() ?? '';
    if (errorCode != '0') {
      throw StateError('$displayName 错误码：$errorCode');
    }
    final translated = (payload['translation'] as List<Object?>? ?? const [])
        .whereType<String>()
        .join('\n');
    if (translated.trim().isEmpty) throw StateError('$displayName 返回空译文');
    return PythiaTranslationResult(
      serviceId: id,
      serviceName: displayName,
      text: translated.trim(),
    );
  }

  static String _defaultYoudaoSalt() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  static int _defaultEpochSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

class OpenAICompatibleTranslationProvider implements TranslationProvider {
  @override
  final String id;
  @override
  final String displayName;
  final String baseUrl;
  final String model;
  final CredentialStore credentialStore;
  final http.Client httpClient;

  const OpenAICompatibleTranslationProvider({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.credentialStore,
    required this.httpClient,
  });

  @override
  Future<PythiaTranslationResult> translate(
      PythiaTranslationRequest request) async {
    final apiKey = await credentialStore.readSecret('provider.$id.apiKey');
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('$displayName 缺少 API Key');
    }
    final uri = _chatCompletionsUri();
    final response = await httpClient
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'system',
                'content':
                    'Translate from ${request.sourceLanguage} to ${request.targetLanguage}. Return only the translation.',
              },
              {'role': 'user', 'content': request.text},
            ],
            'temperature': 0.1,
          }),
        )
        .timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          '$displayName HTTP ${response.statusCode}: ${response.body}');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final choices = payload['choices'] as List<Object?>? ?? const [];
    if (choices.isEmpty) throw StateError('$displayName 返回为空');
    final choice = choices.first as Map<String, Object?>;
    final message = choice['message'] as Map<String, Object?>? ?? const {};
    final text = message['content'] as String? ?? '';
    if (text.trim().isEmpty) throw StateError('$displayName 返回空译文');
    return PythiaTranslationResult(
      serviceId: id,
      serviceName: displayName,
      text: text.trim(),
      model: model,
    );
  }

  Uri _chatCompletionsUri() {
    final trimmed = baseUrl.trim();
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return Uri.parse('$normalized/chat/completions');
  }
}

class DeepLTranslationProvider implements TranslationProvider {
  @override
  String get id => 'deepl';

  @override
  String get displayName => 'DeepL';

  final String baseUrl;
  final CredentialStore credentialStore;
  final http.Client httpClient;

  const DeepLTranslationProvider({
    required this.baseUrl,
    required this.credentialStore,
    required this.httpClient,
  });

  @override
  Future<PythiaTranslationResult> translate(
      PythiaTranslationRequest request) async {
    final apiKey = await credentialStore.readSecret('provider.deepl.apiKey');
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('$displayName 缺少 API Key');
    }
    final parameters = <String, String>{
      'text': request.text,
      'target_lang': _deepLLanguage(request.targetLanguage, target: true),
    };
    if (request.sourceLanguage.toLowerCase() != 'auto') {
      parameters['source_lang'] =
          _deepLLanguage(request.sourceLanguage, target: false);
    }
    final response = await httpClient
        .post(
          _endpointUri(baseUrl, 'translate'),
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: parameters,
        )
        .timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          '$displayName HTTP ${response.statusCode}: ${response.body}');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final translations = payload['translations'] as List<Object?>? ?? const [];
    final first = translations.firstOrNull as Map<String, Object?>?;
    final text = first?['text'] as String? ?? '';
    if (text.trim().isEmpty) throw StateError('$displayName 返回空译文');
    return PythiaTranslationResult(
      serviceId: id,
      serviceName: displayName,
      text: text.trim(),
    );
  }
}

class LibreTranslateTranslationProvider implements TranslationProvider {
  @override
  String get id => 'libretranslate';

  @override
  String get displayName => 'LibreTranslate';

  final String baseUrl;
  final CredentialStore credentialStore;
  final http.Client httpClient;

  const LibreTranslateTranslationProvider({
    required this.baseUrl,
    required this.credentialStore,
    required this.httpClient,
  });

  @override
  Future<PythiaTranslationResult> translate(
      PythiaTranslationRequest request) async {
    final apiKey =
        await credentialStore.readSecret('provider.libretranslate.apiKey');
    final body = <String, Object?>{
      'q': request.text,
      'source': _libreLanguage(request.sourceLanguage),
      'target': _libreLanguage(request.targetLanguage),
      'format': 'text',
      if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
    };
    final response = await httpClient
        .post(
          _endpointUri(baseUrl, 'translate'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          '$displayName HTTP ${response.statusCode}: ${response.body}');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final text = payload['translatedText'] as String? ?? '';
    if (text.trim().isEmpty) throw StateError('$displayName 返回空译文');
    return PythiaTranslationResult(
      serviceId: id,
      serviceName: displayName,
      text: text.trim(),
    );
  }
}

Uri _endpointUri(String baseUrl, String endpoint) {
  final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (normalized.isEmpty) throw StateError('服务地址不能为空');
  if (normalized.endsWith('/$endpoint')) return Uri.parse(normalized);
  return Uri.parse('$normalized/$endpoint');
}

String _deepLLanguage(String code, {required bool target}) {
  final normalized = code.toLowerCase().replaceAll('_', '-');
  return switch (normalized) {
    'zh-cn' => target ? 'ZH-HANS' : 'ZH',
    'zh-tw' || 'zh-hk' => target ? 'ZH-HANT' : 'ZH',
    _ => normalized.split('-').first.toUpperCase(),
  };
}

String _libreLanguage(String code) {
  final normalized = code.toLowerCase().replaceAll('_', '-');
  if (normalized.startsWith('zh-')) return 'zh';
  return normalized.split('-').first;
}

String _baiduLanguage(String code) {
  final normalized = code.toLowerCase().replaceAll('_', '-');
  if (normalized.isEmpty || normalized == 'auto') return 'auto';
  if (normalized.startsWith('zh')) return 'zh';
  if (normalized.startsWith('en')) return 'en';
  if (normalized.startsWith('ja')) return 'jp';
  if (normalized.startsWith('ko')) return 'kor';
  return normalized.split('-').first;
}

String _youdaoLanguage(String code, {required bool source}) {
  final normalized = code.toLowerCase().replaceAll('_', '-');
  if (source && (normalized.isEmpty || normalized == 'auto')) return 'auto';
  if (normalized.startsWith('zh')) return 'zh-CHS';
  if (normalized.startsWith('en')) return 'en';
  if (normalized.startsWith('ja')) return 'ja';
  if (normalized.startsWith('ko')) return 'ko';
  return normalized.isEmpty ? (source ? 'auto' : 'zh-CHS') : normalized;
}

String _truncateForYoudao(String text) {
  final runes = text.runes.toList(growable: false);
  if (runes.length <= 20) return text;
  return '${String.fromCharCodes(runes.take(10))}'
      '${runes.length}'
      '${String.fromCharCodes(runes.skip(runes.length - 10))}';
}

class TranslationServiceRegistry {
  final Map<String, TranslationProvider> _providers;

  TranslationServiceRegistry(Iterable<TranslationProvider> providers)
      : _providers = {for (final provider in providers) provider.id: provider};

  List<TranslationProvider> enabledProviders(List<String> orderedIds) {
    return [
      for (final id in orderedIds)
        if (_providers[id] != null) _providers[id]!,
    ];
  }

  Future<List<PythiaTranslationResult>> translateAll({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
    required List<String> serviceIds,
  }) async {
    final providers = enabledProviders(serviceIds);
    if (providers.isEmpty) throw StateError('没有启用翻译服务');
    final languages = resolvedLanguages(
      text: text,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    final request = PythiaTranslationRequest(
      text: text,
      sourceLanguage: languages.source,
      targetLanguage: languages.target,
      serviceId: '',
    );
    final results = <PythiaTranslationResult>[];
    final errors = <String>[];
    for (final provider in providers) {
      try {
        results.add(await provider.translate(PythiaTranslationRequest(
          text: request.text,
          sourceLanguage: request.sourceLanguage,
          targetLanguage: request.targetLanguage,
          serviceId: provider.id,
        )));
      } catch (error) {
        errors.add('${provider.displayName}: $error');
      }
    }
    if (results.isEmpty) {
      throw StateError(errors.join('\n'));
    }
    return results;
  }

  static PythiaLanguagePair resolvedLanguages({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    final source = _normalizedLanguageCode(sourceLanguage, 'auto');
    final target = _normalizedLanguageCode(targetLanguage, 'zh-CN');
    if (!_isAutoLanguage(source)) {
      return PythiaLanguagePair(source: source, target: target);
    }
    final signals = _languageSignals(text);
    if (signals.hasChinese && !signals.hasEnglish) {
      return PythiaLanguagePair(source: source, target: 'en');
    }
    if (signals.hasEnglish && !signals.hasChinese) {
      return PythiaLanguagePair(source: source, target: 'zh-CN');
    }
    if (signals.hasChinese && signals.hasEnglish) {
      if (_isEnglishLanguage(target)) {
        return PythiaLanguagePair(source: 'zh-CN', target: target);
      }
      if (_isChineseLanguage(target)) {
        return PythiaLanguagePair(source: 'en', target: target);
      }
    }
    return PythiaLanguagePair(source: source, target: target);
  }

  static String _normalizedLanguageCode(String raw, String fallback) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;
    return trimmed.replaceAll('_', '-');
  }

  static bool _isAutoLanguage(String code) {
    return code.toLowerCase() == 'auto';
  }

  static bool _isEnglishLanguage(String code) {
    final normalized = code.toLowerCase();
    return normalized == 'en' || normalized.startsWith('en-');
  }

  static bool _isChineseLanguage(String code) {
    final normalized = code.toLowerCase();
    return normalized == 'zh' || normalized.startsWith('zh-');
  }

  static ({bool hasChinese, bool hasEnglish}) _languageSignals(String text) {
    var hasChinese = false;
    var hasEnglish = false;
    for (final rune in text.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x20000 && rune <= 0x2A6DF)) {
        hasChinese = true;
      } else if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        hasEnglish = true;
      }
    }
    return (hasChinese: hasChinese, hasEnglish: hasEnglish);
  }
}
