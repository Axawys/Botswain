import 'dart:async';

import '../api/control_api_client.dart';
import '../models/health_status.dart';
import 'local_docker.dart';

/// Фаза активации локального агента (для индикации в UI).
enum LocalAgentPhase {
  /// Агент не активирован.
  idle,

  /// Проверяем локальный Docker.
  checkingDocker,

  /// Docker недоступен.
  dockerMissing,

  /// Нет образа агента локально.
  imageMissing,

  /// Запускаем контейнер агента.
  startingAgent,

  /// Ждём health.
  waitingHealth,

  /// Агент жив.
  healthy,

  /// Не удалось активировать.
  failed,
}

/// Снимок состояния локального агента.
class LocalAgentStatus {
  const LocalAgentStatus(this.phase, {this.message, this.health});

  final LocalAgentPhase phase;
  final String? message;
  final HealthStatus? health;

  bool get isActive => phase == LocalAgentPhase.healthy;
}

/// Управляет локальным агентом на ПК пользователя: активация (docker run +
/// health) и отзыв (docker rm). Тот же control-API, что и в серверном режиме,
/// но без SSH-туннеля — клиент ходит напрямую на loopback.
class LocalAgentManager {
  LocalAgentManager({
    LocalDocker docker = const LocalDocker(),
    this.port = 8080,
    this.containerName = 'botswain-agent-local',
    this.image = 'botswain-agent:latest',
  }) : _docker = docker;

  final LocalDocker _docker;
  final int port;
  final String containerName;
  final String image;

  final _statusController = StreamController<LocalAgentStatus>.broadcast();
  LocalAgentStatus _status = const LocalAgentStatus(LocalAgentPhase.idle);

  ControlApiClient? _api;

  Stream<LocalAgentStatus> get statuses => _statusController.stream;
  LocalAgentStatus get status => _status;

  /// Клиент control-API локального агента (доступен после [activate]).
  ControlApiClient? get api => _api;

  void _emit(LocalAgentStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  /// Активирует локального агента: проверка Docker → образ → запуск → health.
  Future<void> activate() async {
    _emit(const LocalAgentStatus(LocalAgentPhase.checkingDocker));
    if (!await _docker.isAvailable()) {
      _emit(const LocalAgentStatus(
        LocalAgentPhase.dockerMissing,
        message: 'Локальный Docker недоступен. Установите и запустите Docker.',
      ));
      throw StateError('docker unavailable');
    }

    if (!await _docker.imageExists(image)) {
      _emit(LocalAgentStatus(
        LocalAgentPhase.imageMissing,
        message: 'Нет образа $image. Соберите его: '
            'cd agent && docker build -t $image .',
      ));
      throw StateError('image missing');
    }

    _emit(const LocalAgentStatus(LocalAgentPhase.startingAgent));
    try {
      await _docker.runAgent(name: containerName, port: port, image: image);
    } catch (e) {
      _emit(LocalAgentStatus(LocalAgentPhase.failed, message: '$e'));
      rethrow;
    }

    _api = ControlApiClient(baseUri: Uri.parse('http://127.0.0.1:$port'));

    _emit(const LocalAgentStatus(LocalAgentPhase.waitingHealth));
    try {
      final health = await _api!.waitUntilHealthy();
      _emit(LocalAgentStatus(LocalAgentPhase.healthy, health: health));
    } catch (e) {
      _emit(LocalAgentStatus(LocalAgentPhase.failed, message: '$e'));
      rethrow;
    }
  }

  /// Отзывает локального агента: удаляет его контейнер. Боты (соседние
  /// контейнеры) при этом не трогаются — их удаляет пользователь из списка.
  Future<void> deactivate() async {
    await _docker.removeAgent(containerName);
    _api?.close();
    _api = null;
    _emit(const LocalAgentStatus(LocalAgentPhase.idle));
  }

  Future<void> dispose() async {
    _api?.close();
    if (!_statusController.isClosed) await _statusController.close();
  }
}
