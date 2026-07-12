import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pythia_windows/core/update_checker.dart';

void main() {
  test('checks latest Pythia GitHub release and compares versions', () async {
    final checker = PythiaUpdateChecker(
      currentVersion: '1.0.0',
      client: MockClient((request) async {
        expect(
          request.url,
          Uri.parse(
              'https://api.github.com/repos/douxy1994/Pythia/releases/latest'),
        );
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.0.1',
            'name': 'Pythia 1.0.1',
            'html_url':
                'https://github.com/douxy1994/Pythia/releases/tag/v1.0.1',
            'assets': [
              {
                'name': 'Pythia-1.0.1-windows-x64.exe',
                'browser_download_url':
                    'https://github.com/douxy1994/Pythia/releases/download/v1.0.1/Pythia-1.0.1-windows-x64.exe',
                'size': 1024,
              },
              {
                'name': 'Pythia-1.0.1-windows-x64.exe.sha256',
                'browser_download_url':
                    'https://github.com/douxy1994/Pythia/releases/download/v1.0.1/Pythia-1.0.1-windows-x64.exe.sha256',
                'size': 96,
              },
            ],
          }),
          200,
        );
      }),
    );

    final info = await checker.check();

    expect(info.currentVersion, '1.0.0');
    expect(info.latestVersion, '1.0.1');
    expect(info.releaseName, 'Pythia 1.0.1');
    expect(info.isNewer, isTrue);
    expect(info.installer?.name, 'Pythia-1.0.1-windows-x64.exe');
    expect(info.installer?.size, 1024);
    expect(info.installer?.checksumUrl.path, endsWith('.exe.sha256'));
    expect(
      info.releaseUrl,
      Uri.parse('https://github.com/douxy1994/Pythia/releases/tag/v1.0.1'),
    );
  });

  test('does not offer installer without exact x64 checksum pair', () async {
    final checker = PythiaUpdateChecker(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'tag_name': 'v1.0.1',
              'html_url': pythiaReleasesUrl,
              'assets': [
                {
                  'name': 'Pythia-1.0.1-windows-arm64.exe',
                  'browser_download_url':
                      'https://github.com/Pythia-windows-arm64.exe',
                  'size': 100,
                },
                {
                  'name': 'Pythia-1.0.1-windows-x64.exe',
                  'browser_download_url':
                      'https://github.com/Pythia-windows-x64.exe',
                  'size': 100,
                },
              ],
            }),
            200,
          )),
    );

    expect((await checker.check()).installer, isNull);
  });

  test('version comparison handles multi-digit segments', () {
    expect(PythiaUpdateChecker.compareVersions('1.0.10', '1.0.2'), 1);
    expect(PythiaUpdateChecker.compareVersions('v1.0.0', '1.0.0'), 0);
    expect(PythiaUpdateChecker.compareVersions('1.0.0', '1.0.1'), -1);
  });

  test('reports HTTP failure from release API', () async {
    final checker = PythiaUpdateChecker(
      client: MockClient((request) async => http.Response('', 500)),
    );

    expect(checker.check(), throwsA(isA<StateError>()));
  });
}
