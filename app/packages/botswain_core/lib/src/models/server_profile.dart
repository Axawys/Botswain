import 'package:meta/meta.dart';

/// Профиль сервера, к которому подключается клиент.
///
/// Пароль и приватный ключ здесь НЕ хранятся — только ссылка на секрет в
/// защищённом хранилище (см. `SecretsStore`). Сам профиль можно спокойно
/// сериализовать в обычный конфиг.
@immutable
class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.host,
    required this.port,
    required this.username,
    this.agentPort = 8080,
  });

  /// Стабильный идентификатор профиля (используется как ключ секрета).
  final String id;

  /// IP или доменное имя VPS.
  final String host;

  /// Порт SSH.
  final int port;

  /// Логин SSH.
  final String username;

  /// Порт, на котором агент слушает на стороне сервера (loopback).
  final int agentPort;

  ServerProfile copyWith({
    String? host,
    int? port,
    String? username,
    int? agentPort,
  }) {
    return ServerProfile(
      id: id,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      agentPort: agentPort ?? this.agentPort,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'host': host,
        'port': port,
        'username': username,
        'agent_port': agentPort,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
        id: json['id'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        agentPort: json['agent_port'] as int? ?? 8080,
      );
}
