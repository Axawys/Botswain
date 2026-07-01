import 'dart:async';

import 'api/control_api_client.dart';
import 'bootstrap/bootstrap.dart';
import 'models/health_status.dart';
import 'models/server_profile.dart';
import 'secrets/secrets_store.dart';
import 'ssh/ssh_client.dart';
import 'tunnel/tunnel.dart';
import 'util/backoff.dart';

/// Фаза сквозного подключения к серверу (для индикации в UI).
enum ConnectionPhase {
  idle,

  /// Установка SSH-сессии для bootstrap.
  connecting,

  /// Проверка наличия Docker на сервере.
  checkingDocker,

  /// Docker не установлен — нужна установка (в M1 — вручную).
  dockerMissing,

  /// Запуск контейнера агента.
  startingAgent,

  /// Поднятие SSH-туннеля к агенту.
  openingTunnel,

  /// Ожидание первого health=ok.
  waitingHealth,

  /// Агент жив и отвечает.
  healthy,

  /// Туннель оборвался, идёт переподключение.
  reconnecting,

  /// Подключение не удалось (см. [ConnectionStatus.message]).
  failed,
}

/// Снимок состояния подключения.
class ConnectionStatus {
  const ConnectionStatus(this.phase, {this.message, this.health});

  final ConnectionPhase phase;

  /// Человекочитаемое пояснение (ошибка, версия Docker и т.п.).
  final String? message;

  /// Последний успешный health, если есть.
  final HealthStatus? health;
}

/// Оркестрирует сквозной путь M1: SSH → проверка Docker → запуск агента →
/// туннель → health → индикация «агент жив».
///
/// Держит устойчивость к разрыву туннеля: [Tunnel] сам переподключается с
/// backoff, а менеджер при восстановлении заново дожидается health и обновляет
/// статус.
class ConnectionManager {
  ConnectionManager({
    required this.profile,
    required SecretsStore secrets,
  }) : _secrets = secrets;

  final ServerProfile profile;
  final SecretsStore _secrets;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = const ConnectionStatus(ConnectionPhase.idle);

  Tunnel? _tunnel;
  ControlApiClient? _api;
  StreamSubscription<TunnelState>? _tunnelSub;

  /// Поток изменений состояния подключения.
  Stream<ConnectionStatus> get statuses => _statusController.stream;
  ConnectionStatus get status => _status;

  /// Клиент control-API для работы с ботами. Доступен после успешного
  /// [connect] (когда поднят туннель); до этого — `null`.
  ControlApiClient? get api => _api;

  void _emit(ConnectionStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  /// Запускает весь поток подключения. Возвращается после первого health=ok
  /// либо бросает исключение при неустранимой ошибке (нет Docker, нет кредов).
  Future<void> connect() async {
    final creds = await _secrets.readSshCredentials(profile.id);
    if (creds == null) {
      _emit(const ConnectionStatus(
        ConnectionPhase.failed,
        message: 'нет сохранённых учётных данных для этого сервера',
      ));
      throw StateError('нет учётных данных');
    }

    // --- Bootstrap на отдельной SSH-сессии ---
    _emit(const ConnectionStatus(ConnectionPhase.connecting));
    final bootstrapSsh = await SshConnection.connect(profile, creds);
    try {
      final bootstrap = ServerBootstrap(bootstrapSsh);

      _emit(const ConnectionStatus(ConnectionPhase.checkingDocker));
      final docker = await bootstrap.checkDocker();
      if (!docker.installed) {
        _emit(const ConnectionStatus(
          ConnectionPhase.dockerMissing,
          message: 'Docker не найден на сервере. Установите его и повторите.',
        ));
        throw StateError('docker не установлен');
      }

      _emit(ConnectionStatus(
        ConnectionPhase.startingAgent,
        message: docker.version,
      ));
      await bootstrap.runAgent(profile);
    } finally {
      // Bootstrap-сессия больше не нужна: туннель поднимает свою.
      await bootstrapSsh.close();
    }

    // --- Туннель (со своей SSH-сессией и автопереподключением) ---
    _emit(const ConnectionStatus(ConnectionPhase.openingTunnel));
    final tunnel = Tunnel(
      connect: () => SshConnection.connect(profile, creds),
      remoteHost: '127.0.0.1',
      remotePort: profile.agentPort,
    );
    _tunnel = tunnel;
    _tunnelSub = tunnel.states.listen(_onTunnelState);
    await tunnel.start();

    _api = ControlApiClient(baseUri: tunnel.localBaseUri);

    // --- Первый health ---
    _emit(const ConnectionStatus(ConnectionPhase.waitingHealth));
    final health = await _api!.waitUntilHealthy();
    _emit(ConnectionStatus(ConnectionPhase.healthy, health: health));
  }

  /// Реакция на изменения состояния туннеля: при переподключении показываем
  /// это в UI, при восстановлении — заново дожидаемся health.
  void _onTunnelState(TunnelState state) {
    switch (state) {
      case TunnelState.reconnecting:
        _emit(const ConnectionStatus(ConnectionPhase.reconnecting));
      case TunnelState.connected:
        // Туннель восстановился — пере-подтверждаем живость агента.
        if (_status.phase == ConnectionPhase.reconnecting) {
          unawaited(_recheckHealth());
        }
      case TunnelState.connecting:
      case TunnelState.closed:
        break;
    }
  }

  Future<void> _recheckHealth() async {
    final api = _api;
    if (api == null) return;
    try {
      _emit(const ConnectionStatus(ConnectionPhase.waitingHealth));
      final health = await api.waitUntilHealthy(
        backoff: Backoff(),
      );
      _emit(ConnectionStatus(ConnectionPhase.healthy, health: health));
    } catch (e) {
      _emit(ConnectionStatus(ConnectionPhase.failed, message: '$e'));
    }
  }

  /// Разовый опрос health (для кнопки «проверить» в UI).
  Future<HealthStatus> checkHealthOnce() {
    final api = _api;
    if (api == null) {
      throw StateError('подключение не установлено');
    }
    return api.health();
  }

  /// Закрывает туннель, API-клиент и поток статусов. Идемпотентно.
  Future<void> dispose() async {
    await _tunnelSub?.cancel();
    await _tunnel?.close();
    _api?.close();
    if (!_statusController.isClosed) await _statusController.close();
  }
}
