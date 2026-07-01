import 'dart:io';

/// Тонкая обёртка над локальным Docker CLI для локального режима.
///
/// В отличие от серверного режима (bootstrap по SSH), локальный агент
/// поднимается прямо на ПК пользователя: команды docker выполняются локальным
/// процессом, транспорт к control-API — без туннеля.
class LocalDocker {
  const LocalDocker();

  /// Доступен ли локальный Docker-демон.
  Future<bool> isAvailable() async {
    try {
      final r = await Process.run(
        'docker',
        ['version', '--format', '{{.Server.Version}}'],
      );
      return r.exitCode == 0;
    } catch (_) {
      // docker не в PATH / не установлен.
      return false;
    }
  }

  /// Есть ли образ локально.
  Future<bool> imageExists(String image) async {
    try {
      final r = await Process.run('docker', ['image', 'inspect', image]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Запускает (пересоздаёт) контейнер агента локально.
  ///
  /// Публикуем только на loopback хоста, монтируем docker.sock — агент рулит
  /// ботами как соседними контейнерами. Внутри контейнера агент слушает 8080.
  Future<void> runAgent({
    required String name,
    required int port,
    required String image,
  }) async {
    await removeAgent(name); // идемпотентность: убираем прежний, если остался
    final r = await Process.run('docker', [
      'run',
      '-d',
      '--name',
      name,
      '--restart',
      'unless-stopped',
      '-p',
      '127.0.0.1:$port:8080',
      '-v',
      '/var/run/docker.sock:/var/run/docker.sock',
      image,
    ]);
    if (r.exitCode != 0) {
      throw StateError('docker run: ${_text(r.stderr)}');
    }
  }

  /// Удаляет контейнер агента (отзыв). Ошибку отсутствия игнорируем.
  Future<void> removeAgent(String name) async {
    try {
      await Process.run('docker', ['rm', '-f', name]);
    } catch (_) {
      // docker недоступен — считаем, что удалять нечего.
    }
  }

  /// Запущен ли контейнер агента.
  Future<bool> isRunning(String name) async {
    try {
      final r = await Process.run(
        'docker',
        ['ps', '-q', '--filter', 'name=^/$name\$'],
      );
      return r.exitCode == 0 && _text(r.stdout).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _text(Object? out) => out is String ? out : '';
}
