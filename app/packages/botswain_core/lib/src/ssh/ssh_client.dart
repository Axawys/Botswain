import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../models/server_profile.dart';
import '../secrets/secrets_store.dart';

/// Результат выполнения команды по SSH.
class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// Тонкая обёртка над [SSHClient] из dartssh2.
///
/// Отвечает только за установку SSH-сессии и выполнение команд bootstrap'а
/// и за открытие direct-tcpip каналов для туннеля. Произвольный шелл из UI
/// сюда не приходит — команды формирует слой bootstrap (см. docs/architecture.md).
class SshConnection {
  SshConnection._(this._client);

  final SSHClient _client;

  bool get isClosed => _client.isClosed;

  /// Завершается, когда SSH-сессия закрыта (штатно или из-за обрыва).
  /// Туннель использует это для обнаружения разрыва.
  Future<void> get done => _client.done;

  /// Устанавливает SSH-соединение по профилю и учётным данным.
  ///
  /// Поддерживает аутентификацию паролем или приватным ключом. Бросает
  /// исключение dartssh2 при неудаче — вызывающий слой решает, что показать.
  static Future<SshConnection> connect(
    ServerProfile profile,
    SshCredentials creds,
  ) async {
    final socket = await SSHSocket.connect(profile.host, profile.port);

    final identities = <SSHKeyPair>[];
    if (creds.hasPrivateKey) {
      identities.addAll(
        SSHKeyPair.fromPem(creds.privateKey!, creds.passphrase),
      );
    }

    final client = SSHClient(
      socket,
      username: profile.username,
      identities: identities.isEmpty ? null : identities,
      // Пароль запрашивается по требованию сервера.
      onPasswordRequest: creds.hasPassword ? () => creds.password! : null,
    );

    await client.authenticated;
    return SshConnection._(client);
  }

  /// Выполняет команду и собирает stdout/stderr/exit code целиком.
  ///
  /// Подходит для коротких команд bootstrap'а (`docker --version`,
  /// `docker run ...`). Для стриминга (логи ботов) появится отдельный путь в M3.
  Future<CommandResult> run(String command) async {
    final session = await _client.execute(command);

    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final stdoutDone =
        utf8.decoder.bind(session.stdout).forEach(stdout.write);
    final stderrDone =
        utf8.decoder.bind(session.stderr).forEach(stderr.write);

    await session.done;
    await Future.wait([stdoutDone, stderrDone]);

    return CommandResult(
      exitCode: session.exitCode ?? -1,
      stdout: stdout.toString(),
      stderr: stderr.toString(),
    );
  }

  /// Открывает direct-tcpip канал к `host:port` на стороне сервера.
  /// Используется туннелем для проброса к агенту на loopback VPS.
  Future<SSHForwardChannel> forwardLocal(String host, int port) {
    return _client.forwardLocal(host, port);
  }

  Future<void> close() async {
    _client.close();
    await _client.done;
  }
}
