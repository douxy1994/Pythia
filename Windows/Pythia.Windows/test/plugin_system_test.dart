import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pythia_windows/core/plugin_system.dart';
import 'package:pythia_windows/core/translation_service.dart';
import 'package:pythia_windows/platform/credential_store.dart';

void main() {
  late Directory sandbox;
  late Directory plugins;
  late File runner;
  late String node;
  late MemoryCredentialStore credentials;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('pythia-plugin-test-');
    plugins = Directory(p.join(sandbox.path, 'Plugins'));
    runner = File(p.normalize(p.join(
      Directory.current.path,
      'assets',
      'pythia-plugin-runner.cjs',
    )));
    node = (await Process.run('which', ['node'])).stdout.toString().trim();
    credentials = MemoryCredentialStore();
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  PythiaPluginManager createManager({
    PotextConverter? converter,
    Duration Function(String)? timeout,
  }) {
    return PythiaPluginManager(
      rootDirectory: plugins,
      runnerFile: runner,
      nodeExecutable: node,
      credentialStore: credentials,
      convertPotext: converter,
      timeoutForText: timeout,
    );
  }

  test('validates the cross-platform manifest contract', () {
    final manifest = exampleManifest();
    expect(() => manifest.validate(platform: 'windows'), returnsNormally);
    expect(
      () => exampleManifest(entry: '../outside.js').validate(
        platform: 'windows',
      ),
      throwsFormatException,
    );
    expect(
      () => exampleManifest(permissions: const ['filesystem']).validate(
        platform: 'windows',
      ),
      throwsFormatException,
    );
  });

  test('converts Pot translate metadata into Pythia protocol', () {
    final converted = PotextPluginConverter.convert(
      {
        'id': 'com.example.legacy',
        'display': 'Legacy Translator',
        'version': '1.2.3',
        'plugin_type': 'translate',
        'needs': [
          {'key': 'apiKey', 'display': 'API Key'},
          {'key': 'max_tokens', 'display': 'Max tokens', 'default': '4096'},
          {'key': 'model', 'display': 'Model', 'default': 'test-model'},
        ],
      },
      'async function translate(text) { return text; }',
      'legacy',
    );
    expect(converted.manifest.type, 'translator');
    expect(converted.manifest.permissions, isEmpty);
    expect(converted.manifest.configuration.first.type, 'secret');
    expect(converted.manifest.configuration[1].type, 'text');
    expect(converted.mainJavaScript, contains('__pythiaLegacyTranslate'));
    expect(converted.mainJavaScript, contains('context.fetch'));
  });

  test('installs and runs a native Pythia translator', () async {
    final package = await writePythiaPackage(
      Directory(p.join(sandbox.path, 'echo.pythia')),
      manifest: exampleManifest(),
      source: 'module.exports.translate = async (request) => '
          '`[\${request.input.sourceLanguage}->\${request.input.targetLanguage}] \${request.input.text}`;',
    );
    final manager = createManager();
    await manager.initialize();
    final installed = await manager.install(package);
    final text = await manager.translate(
      installed.plugin,
      const PythiaTranslationRequest(
        text: 'hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh-CN',
        serviceId: 'plugin:com.example.echo',
      ),
    );
    expect(text, '[en->zh-CN] hello');
  });

  test('converts Potext, preserves backup, and prefers Pythia package',
      () async {
    final potext = await writePotextPackage(
      Directory(p.join(sandbox.path, 'arbitrary-name.potext')),
    );
    final manager = createManager();
    await manager.initialize();
    final result = await manager.install(potext);
    expect(result.converted, isTrue);
    expect(result.plugin.format, PythiaPluginPackageFormat.pythia);
    expect(
      File(p.join(
        manager.backupDirectory.path,
        'arbitrary-name.potext',
      )).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(result.plugin.directory.path, 'legacy-main.js')).existsSync(),
      isTrue,
    );
    final installed = await manager.listInstalled();
    expect(
      installed.where((item) => item.manifest.id == 'com.example.legacy'),
      hasLength(1),
    );
    expect(installed.single.format, PythiaPluginPackageFormat.pythia);
  });

  test('native Pythia package wins when the same Potext id is imported',
      () async {
    final native = await writePythiaPackage(
      Directory(p.join(sandbox.path, 'native.pythia')),
      manifest: exampleManifest(
        id: 'com.example.legacy',
        name: 'Native Preferred',
      ),
      source: 'module.exports.translate = async () => "native";',
    );
    final potext = await writePotextPackage(
      Directory(p.join(sandbox.path, 'legacy.potext')),
    );
    final manager = createManager();
    await manager.initialize();
    await manager.install(native);
    await manager.install(potext);
    final installed = await manager.listInstalled();
    final plugin = installed.singleWhere(
      (item) => item.manifest.id == 'com.example.legacy',
    );
    expect(plugin.manifest.name, 'Native Preferred');
    expect(plugin.conversionStatus, 'native');
    expect(
      await manager.translate(
        plugin,
        const PythiaTranslationRequest(
          text: 'hello',
          sourceLanguage: 'en',
          targetLanguage: 'zh-CN',
          serviceId: '',
        ),
      ),
      'native',
    );
  });

  test('keeps a usable compatibility package when strict conversion fails',
      () async {
    final potext = await writePotextPackage(
      Directory(p.join(sandbox.path, 'fallback.potext')),
    );
    final manager = createManager(
      converter: (_, __, ___) => throw const FormatException('forced failure'),
    );
    await manager.initialize();
    final result = await manager.install(potext);
    expect(result.compatibilityFallback, isTrue);
    expect(result.plugin.format, PythiaPluginPackageFormat.potext);
    final text = await manager.translate(
      result.plugin,
      const PythiaTranslationRequest(
        text: 'hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh-CN',
        serviceId: 'plugin:com.example.legacy',
      ),
    );
    expect(text, '[en->zh-CN] hello');
  });

  test('stores plugin secrets only in the credential store', () async {
    final secureManifest = exampleManifest(configuration: const [
      PythiaPluginConfigurationField(
        key: 'apiKey',
        label: 'API Key',
        type: 'secret',
        required: true,
      ),
      PythiaPluginConfigurationField(
        key: 'model',
        label: 'Model',
        type: 'text',
        required: true,
      ),
    ]);
    final package = await writePythiaPackage(
      Directory(p.join(sandbox.path, 'secure.pythia')),
      manifest: secureManifest,
      source: 'module.exports.translate = async () => "ok";',
    );
    final manager = createManager();
    await manager.initialize();
    await manager.install(package);
    await manager.saveConfiguration(secureManifest, {
      'apiKey': 'test-secret-value',
      'model': 'test-model',
    });
    final state =
        await File(p.join(plugins.path, 'plugin-state.json')).readAsString();
    expect(state, contains('test-model'));
    expect(state, isNot(contains('test-secret-value')));
    expect(
      credentials.values['plugin.com.example.echo.apiKey'],
      'test-secret-value',
    );
    final restored = await manager.configurationFor(secureManifest);
    expect(restored['apiKey'], 'test-secret-value');
  });

  test('isolates runtime errors and timeouts without disabling other plugins',
      () async {
    final failing = await writePythiaPackage(
      Directory(p.join(sandbox.path, 'failing.pythia')),
      manifest: exampleManifest(id: 'com.example.failing', name: 'Failing'),
      source:
          'module.exports.translate = async () => { throw new Error("boom"); };',
    );
    final hanging = await writePythiaPackage(
      Directory(p.join(sandbox.path, 'hanging.pythia')),
      manifest: exampleManifest(id: 'com.example.hanging', name: 'Hanging'),
      source: 'module.exports.translate = async () => new Promise(() => {});',
    );
    final healthy = await writePythiaPackage(
      Directory(p.join(sandbox.path, 'healthy.pythia')),
      manifest: exampleManifest(id: 'com.example.healthy', name: 'Healthy'),
      source: 'module.exports.translate = async () => "healthy";',
    );
    final manager = createManager(
      timeout: (_) => const Duration(milliseconds: 150),
    );
    await manager.initialize();
    final failed = await manager.install(failing);
    final hung = await manager.install(hanging);
    final good = await manager.install(healthy);
    const request = PythiaTranslationRequest(
      text: 'hello',
      sourceLanguage: 'en',
      targetLanguage: 'zh-CN',
      serviceId: '',
    );
    await expectLater(
        manager.translate(failed.plugin, request), throwsStateError);
    await expectLater(
        manager.translate(hung.plugin, request), throwsStateError);
    expect(await manager.translate(good.plugin, request), 'healthy');
  });

  test('Windows and macOS bundle the exact same plugin runner', () async {
    final macRunner = File(p.normalize(p.join(
      Directory.current.path,
      '..',
      '..',
      'Pythia',
      'Resources',
      'pythia-plugin-runner.cjs',
    )));
    expect(await runner.readAsBytes(), await macRunner.readAsBytes());
  });
}

PythiaPluginManifest exampleManifest({
  String id = 'com.example.echo',
  String name = 'Echo',
  String entry = 'main.js',
  List<String> permissions = const [],
  List<PythiaPluginConfigurationField> configuration = const [],
}) {
  return PythiaPluginManifest(
    schemaVersion: '1.0',
    id: id,
    name: name,
    version: '1.0.0',
    description: 'Test plugin.',
    author: 'Pythia Tests',
    type: 'translator',
    entry: entry,
    minimumPythiaVersion: '1.0.0',
    supportedPlatforms: const ['macos', 'windows'],
    permissions: permissions,
    configuration: configuration,
    capabilities: const ['translate'],
  );
}

Future<Directory> writePythiaPackage(
  Directory directory, {
  required PythiaPluginManifest manifest,
  required String source,
}) async {
  await directory.create(recursive: true);
  await File(p.join(directory.path, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
  );
  await File(p.join(directory.path, manifest.entry)).writeAsString(source);
  return directory;
}

Future<Directory> writePotextPackage(Directory directory) async {
  await directory.create(recursive: true);
  await File(p.join(directory.path, 'info.json')).writeAsString(jsonEncode({
    'id': 'com.example.legacy',
    'display': 'Legacy Echo',
    'version': '1.0.0',
    'plugin_type': 'translate',
    'needs': <Object?>[],
  }));
  await File(p.join(directory.path, 'main.js')).writeAsString(
    'async function translate(text, from, to) { return `[\${from}->\${to}] \${text}`; }',
  );
  return directory;
}

class MemoryCredentialStore implements CredentialStore {
  final Map<String, String> values = {};

  @override
  Future<void> deleteSecret(String key) async => values.remove(key);

  @override
  Future<String?> readSecret(String key) async => values[key];

  @override
  Future<void> writeSecret(String key, String value) async {
    values[key] = value;
  }
}
