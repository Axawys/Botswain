import '../models/server_profile.dart';
import '../ssh/ssh_client.dart';

/// Имя контейнера агента на сервере. Фиксировано, чтобы bootstrap был
/// идемпотентным: повторный запуск переиспользует/пересоздаёт тот же контейнер.
const kAgentContainerName = 'botswain-agent';

/// Имя/тег образа агента. В M1 предполагается, что образ уже доступен на
/// сервере (собран локально или загружен). Публикация в реестр — позже.
const kAgentImage = 'botswain-agent:latest';

/// Результат проверки Docker на сервере.
class DockerCheck {
  const DockerCheck({required this.installed, this.version});

  final bool installed;

  /// Строка версии из `docker --version`, если Docker установлен.
  final String? version;
}

/// Bootstrap сервера по SSH: проверка Docker и запуск контейнера агента.
///
/// Это единственное место, где по SSH выполняются команды. Список команд
/// фиксирован и не приходит из UI (см. docs/architecture.md).
class ServerBootstrap {
  ServerBootstrap(this._ssh);

  final SshConnection _ssh;

  /// Проверяет наличие Docker на сервере через `docker --version`.
  Future<DockerCheck> checkDocker() async {
    final res = await _ssh.run('docker --version');
    if (res.ok) {
      return DockerCheck(installed: true, version: res.stdout.trim());
    }
    return const DockerCheck(installed: false);
  }

  /// Устанавливает Docker на сервере.
  ///
  /// TODO(M1): реализовать установку (например, скрипт get.docker.com под
  /// нужный дистрибутив). Пока — явная заглушка, чтобы поток bootstrap был
  /// виден целиком, но не делал ничего необратимого без ведома пользователя.
  Future<void> installDocker() async {
    throw UnimplementedError(
      'Автоустановка Docker появится позже. Установите Docker на сервере вручную.',
    );
  }

  /// Запускает (или пересоздаёт) контейнер агента.
  ///
  /// Агент биндится внутри контейнера на 0.0.0.0, наружу публикуется только на
  /// loopback хоста (`-p 127.0.0.1:PORT:PORT`) — публично в сеть не торчит.
  /// `--restart unless-stopped` поднимает агента после перезагрузки VPS.
  Future<void> runAgent(ServerProfile profile) async {
    // Убираем предыдущий контейнер, если остался, чтобы docker run не падал на
    // конфликте имени. Ошибку отсутствия контейнера игнорируем.
    await _ssh.run('docker rm -f $kAgentContainerName');

    final port = profile.agentPort;
    final cmd = 'docker run -d '
        '--name $kAgentContainerName '
        '--restart unless-stopped '
        '-p 127.0.0.1:$port:$port '
        '-v /var/run/docker.sock:/var/run/docker.sock '
        '$kAgentImage --host 0.0.0.0 --port $port';

    final res = await _ssh.run(cmd);
    if (!res.ok) {
      throw StateError('не удалось запустить агента: ${res.stderr.trim()}');
    }
  }

  /// Отзывает агента на сервере: удаляет его контейнер. Боты (соседние
  /// контейнеры) не трогаются.
  Future<void> removeAgent() async {
    await _ssh.run('docker rm -f $kAgentContainerName');
  }
}
