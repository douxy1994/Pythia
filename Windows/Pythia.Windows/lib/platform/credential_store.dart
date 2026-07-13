import 'package:flutter/services.dart';

abstract interface class CredentialStore {
  Future<String?> readSecret(String key);
  Future<void> writeSecret(String key, String value);
  Future<void> deleteSecret(String key);
}

class MethodChannelCredentialStore implements CredentialStore {
  static const MethodChannel _channel =
      MethodChannel('pythia/credential_store');

  const MethodChannelCredentialStore();

  @override
  Future<String?> readSecret(String key) {
    return _channel.invokeMethod<String>('readSecret', {'key': key});
  }

  @override
  Future<void> writeSecret(String key, String value) {
    return _channel.invokeMethod<void>('writeSecret', {
      'key': key,
      'value': value,
    });
  }

  @override
  Future<void> deleteSecret(String key) {
    return _channel.invokeMethod<void>('deleteSecret', {'key': key});
  }
}

class UnsupportedCredentialStore implements CredentialStore {
  const UnsupportedCredentialStore();

  Never _missing() {
    throw UnsupportedError(
      'Windows Credential Manager/DPAPI channel is not wired yet. '
      'Do not store API keys in plain settings JSON.',
    );
  }

  @override
  Future<String?> readSecret(String key) async {
    _missing();
  }

  @override
  Future<void> writeSecret(String key, String value) async {
    _missing();
  }

  @override
  Future<void> deleteSecret(String key) async {
    _missing();
  }
}
