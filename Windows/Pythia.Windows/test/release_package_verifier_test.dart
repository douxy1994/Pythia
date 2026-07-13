import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/release_package_verifier.dart';

void main() {
  late Directory packageDir;

  setUp(() async {
    packageDir = await Directory.systemTemp.createTemp('pythia_release_test_');
  });

  tearDown(() async {
    if (await packageDir.exists()) {
      await packageDir.delete(recursive: true);
    }
  });

  test('allows a clean Flutter Windows release layout', () async {
    await writePeExecutable(packageDir, machine: 0x8664);
    await writePackageFile(
      packageDir,
      'data/flutter_assets/AssetManifest.bin',
      'asset manifest',
    );
    await writePackageFile(
      packageDir,
      'path_provider_windows.dll',
      'native dependency placeholder',
    );

    final issues = await ReleasePackageVerifier().verify(packageDir);

    expect(issues, isEmpty);
  });

  test('rejects a non-x64 Windows executable', () async {
    await writePeExecutable(packageDir, machine: 0x014c);

    final issues = await ReleasePackageVerifier().verify(packageDir);

    expect(
      issues.map((issue) => issue.message).join('\n'),
      contains('x64 AMD64'),
    );
  });

  test('rejects bundled potext plugin packages', () async {
    await writePackageFile(
      packageDir,
      'plugins/translate/sample.potext',
      'plugin data',
    );

    final issues = await ReleasePackageVerifier().verify(packageDir);

    expect(
        issues.map((issue) => issue.message).join('\n'), contains('.potext'));
  });

  test('rejects legacy plugin runner and service source trees', () async {
    await writePackageFile(
      packageDir,
      'Resources/legacy-plugin-runner.cjs',
      'runner',
    );
    await writePackageFile(
      packageDir,
      'src/services/translate/openai/index.jsx',
      'legacy source',
    );

    final issues = await ReleasePackageVerifier().verify(packageDir);

    final messages = issues.map((issue) => issue.message).join('\n');
    expect(messages, contains('legacy Pot plugin runner'));
    expect(messages, contains('legacy Pot service/plugin source tree'));
  });

  test('rejects private release secrets in text files', () async {
    await writePackageFile(
      packageDir,
      'config.txt',
      'OPENAI_API_KEY=sk-${'abcdefghijklmnopqrstuvwxyz123456'}',
    );
    await writePackageFile(
        packageDir, 'signing.env', 'TAURI_PRIVATE_KEY=secret');

    final issues = await ReleasePackageVerifier().verify(packageDir);

    final messages = issues.map((issue) => issue.message).join('\n');
    expect(messages, contains('OpenAI-style API key'));
    expect(messages, contains('Tauri private key marker'));
  });

  test('reports missing package directory', () async {
    final missing = Directory('${packageDir.path}/missing');

    final issues = await ReleasePackageVerifier().verify(missing);

    expect(issues.single.message, contains('does not exist'));
  });
}

Future<void> writePackageFile(
  Directory packageDir,
  String relativePath,
  String contents,
) async {
  final file = File('${packageDir.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

Future<void> writePeExecutable(
  Directory packageDir, {
  required int machine,
}) async {
  final bytes = Uint8List(128);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 0x4d;
  bytes[1] = 0x5a;
  data.setUint32(0x3c, 0x40, Endian.little);
  bytes[0x40] = 0x50;
  bytes[0x41] = 0x45;
  data.setUint16(0x44, machine, Endian.little);
  await File('${packageDir.path}/Pythia.exe').writeAsBytes(bytes);
}
