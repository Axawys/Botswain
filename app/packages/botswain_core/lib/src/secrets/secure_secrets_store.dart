import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secrets_store.dart';

/// Реализация [SecretsStore] поверх flutter_secure_storage.
///
/// На Linux бэкендом выступает libsecret (GNOME Keyring / KWallet). Секреты
/// никогда не попадают в обычный конфиг открытым текстом.
class SecureSecretsStore implements SecretsStore {
  SecureSecretsStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              lOptions: LinuxOptions(),
            );

  final FlutterSecureStorage _storage;

  // Ключи внутри хранилища строятся из id профиля, чтобы секреты разных
  // серверов не пересекались.
  String _passwordKey(String id) => 'ssh.$id.password';
  String _privateKeyKey(String id) => 'ssh.$id.private_key';
  String _passphraseKey(String id) => 'ssh.$id.passphrase';

  @override
  Future<void> saveSshCredentials(String profileId, SshCredentials creds) async {
    // Пишем только заданные поля, лишние — удаляем, чтобы не осталось
    // устаревшего пароля при переходе на ключ и наоборот.
    await _writeOrDelete(_passwordKey(profileId), creds.password);
    await _writeOrDelete(_privateKeyKey(profileId), creds.privateKey);
    await _writeOrDelete(_passphraseKey(profileId), creds.passphrase);
  }

  @override
  Future<SshCredentials?> readSshCredentials(String profileId) async {
    final password = await _storage.read(key: _passwordKey(profileId));
    final privateKey = await _storage.read(key: _privateKeyKey(profileId));
    final passphrase = await _storage.read(key: _passphraseKey(profileId));

    if (password == null && privateKey == null) return null;
    return SshCredentials(
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
    );
  }

  @override
  Future<void> deleteForProfile(String profileId) async {
    await _storage.delete(key: _passwordKey(profileId));
    await _storage.delete(key: _privateKeyKey(profileId));
    await _storage.delete(key: _passphraseKey(profileId));
  }

  String _proxiesKey(String contextId) => 'proxies.$contextId';

  @override
  Future<void> saveProxies(String contextId, List<String> proxies) {
    if (proxies.isEmpty) {
      return _storage.delete(key: _proxiesKey(contextId));
    }
    return _storage.write(
      key: _proxiesKey(contextId),
      value: jsonEncode(proxies),
    );
  }

  @override
  Future<List<String>> readProxies(String contextId) async {
    final raw = await _storage.read(key: _proxiesKey(contextId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => '$e').toList();
    } catch (_) {
      // повреждённое значение — считаем, что списка нет
    }
    return const [];
  }

  String _proxySourceKey(String contextId) => 'proxy_source.$contextId';

  @override
  Future<void> saveProxySource(String contextId, String url) {
    if (url.isEmpty) {
      return _storage.delete(key: _proxySourceKey(contextId));
    }
    return _storage.write(key: _proxySourceKey(contextId), value: url);
  }

  @override
  Future<String?> readProxySource(String contextId) {
    return _storage.read(key: _proxySourceKey(contextId));
  }

  Future<void> _writeOrDelete(String key, String? value) {
    if (value == null || value.isEmpty) {
      return _storage.delete(key: key);
    }
    return _storage.write(key: key, value: value);
  }
}
