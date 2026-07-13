import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pythia_windows/core/update_checker.dart';
import 'package:pythia_windows/core/update_installer.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('pythia-update');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('downloads x64 installer after size and SHA-256 verification', () async {
    final payload = utf8.encode('signed installer fixture');
    final checksum = sha256.convert(payload).toString();
    final progress = <int>[];
    final installer = PythiaReleaseInstaller(
      client: MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) {
          return http.Response(
              '$checksum  Pythia-1.0.1-windows-x64.exe\n', 200);
        }
        return http.Response.bytes(payload, 200);
      }),
    );

    final file = await installer.downloadVerified(
      _asset(payload.length),
      temporaryDirectory,
      onProgress: (received, _) => progress.add(received),
    );

    expect(await file.readAsBytes(), payload);
    expect(progress.last, payload.length);
  });

  test('deletes download when SHA-256 does not match', () async {
    final payload = utf8.encode('tampered');
    final installer = PythiaReleaseInstaller(
      client: MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) {
          return http.Response('${'0' * 64}  Pythia.exe', 200);
        }
        return http.Response.bytes(payload, 200);
      }),
    );

    await expectLater(
      installer.downloadVerified(
        _asset(payload.length),
        temporaryDirectory,
      ),
      throwsA(isA<StateError>()),
    );
    expect(temporaryDirectory.listSync(), isEmpty);
  });

  test('rejects untrusted or non-x64 asset metadata', () async {
    final installer = PythiaReleaseInstaller(
      client: MockClient((_) async => http.Response('', 200)),
    );
    await expectLater(
      installer.downloadVerified(
        PythiaInstallerAsset(
          name: 'Pythia-windows-arm64.exe',
          downloadUrl: Uri.parse('http://example.com/Pythia.exe'),
          checksumUrl: Uri.parse('http://example.com/Pythia.exe.sha256'),
          size: 1,
        ),
        temporaryDirectory,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects redirects away from trusted GitHub hosts', () async {
    final installer = PythiaReleaseInstaller(
      client: MockClient((_) async => http.Response(
            '',
            302,
            headers: {'location': 'https://downloads.example.com/update.exe'},
          )),
    );

    await expectLater(
      installer.downloadVerified(_asset(10), temporaryDirectory),
      throwsA(isA<StateError>()),
    );
  });
}

PythiaInstallerAsset _asset(int size) => PythiaInstallerAsset(
      name: 'Pythia-1.0.1-windows-x64.exe',
      downloadUrl: Uri.parse(
        'https://github.com/douxy1994/Pythia/releases/download/v1.0.1/Pythia-1.0.1-windows-x64.exe',
      ),
      checksumUrl: Uri.parse(
        'https://github.com/douxy1994/Pythia/releases/download/v1.0.1/Pythia-1.0.1-windows-x64.exe.sha256',
      ),
      size: size,
    );
