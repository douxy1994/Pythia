import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pythia_windows/core/webdav_portable_backup.dart';
import 'package:pythia_windows/core/webdav_sync.dart';

void main() {
  const credentials = WebDavCredentials(
    baseUrl: 'https://dav.example/root',
    username: 'user',
    password: 'secret',
  );

  test('uploads via temporary file and falls back when MOVE is unsupported',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'MKCOL') return http.Response('', 405);
      if (request.method == 'MOVE') return http.Response('', 405);
      return http.Response('', 204);
    });

    await WebDavPortableBackupService(client: client)
        .upload('{"product":"Pythia"}', credentials);

    expect(requests.map((request) => request.method),
        ['MKCOL', 'MKCOL', 'PUT', 'MOVE', 'PUT', 'DELETE']);
    expect(
        requests[2].url.path, '/root/Pythia/settings/portable-backup.tmp.json');
    expect(requests[3].headers['Destination'],
        'https://dav.example/root/Pythia/settings/portable-backup.json');
    expect(requests[4].url.path, '/root/Pythia/settings/portable-backup.json');
    expect(requests[4].headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('user:secret'))}');
    expect(requests.last.url.path,
        '/root/Pythia/settings/portable-backup.tmp.json');
  });

  test('downloads the portable backup without mutating it', () async {
    const payload = '{"schemaVersion":1,"product":"Pythia"}';
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/root/Pythia/settings/portable-backup.json');
      return http.Response(payload, 200);
    });

    final downloaded =
        await WebDavPortableBackupService(client: client).download(credentials);

    expect(downloaded, payload);
  });

  test('reports missing remote backup clearly', () async {
    final client = MockClient((_) async => http.Response('', 404));

    expect(
      () => WebDavPortableBackupService(client: client).download(credentials),
      throwsA(isA<StateError>()),
    );
  });
}
