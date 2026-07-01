/// Учётные данные SSH для профиля сервера.
///
/// Ровно один из [password] / [privateKey] должен быть задан.
class SshCredentials {
  const SshCredentials({this.password, this.privateKey, this.passphrase});

  final String? password;
  final String? privateKey;

  /// Passphrase приватного ключа, если он зашифрован.
  final String? passphrase;

  bool get hasPassword => password != null && password!.isNotEmpty;
  bool get hasPrivateKey => privateKey != null && privateKey!.isNotEmpty;
}

/// Абстракция защищённого хранилища секретов.
///
/// Вынесена в интерфейс, чтобы ядро не зависело от конкретной реализации:
/// в приложении используется [SecureSecretsStore] поверх flutter_secure_storage,
/// в тестах — фейковая in-memory реализация.
abstract class SecretsStore {
  /// Сохраняет учётные данные SSH для профиля [profileId].
  Future<void> saveSshCredentials(String profileId, SshCredentials creds);

  /// Читает учётные данные SSH; `null`, если ничего не сохранено.
  Future<SshCredentials?> readSshCredentials(String profileId);

  /// Удаляет все секреты профиля.
  Future<void> deleteForProfile(String profileId);
}
