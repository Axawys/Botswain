import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../ssh/ssh_client.dart';
import '../util/backoff.dart';

/// Состояние туннеля для индикации в UI.
enum TunnelState {
  /// Идёт установка SSH-сессии.
  connecting,

  /// Локальный порт слушает, SSH-сессия жива.
  connected,

  /// SSH-сессия оборвалась, идёт переподключение с backoff.
  reconnecting,

  /// Туннель закрыт вызывающим кодом.
  closed,
}

/// SSH port-forward туннель к агенту с автопереподключением.
///
/// Держит локальный слушающий сокет на `127.0.0.1:<localPort>` и для каждого
/// входящего соединения открывает direct-tcpip канал к `remoteHost:remotePort`
/// на стороне сервера. Публично агент не торчит — туннель это и есть
/// аутентификация и шифрование (см. docs/architecture.md).
///
/// Переживает разрыв SSH-сессии: при обрыве переустанавливает её с
/// экспоненциальным backoff. Локальный сокет при этом остаётся поднятым, так
/// что HTTP-клиент может просто повторить запрос.
class Tunnel {
  Tunnel({
    required Future<SshConnection> Function() connect,
    required this.remoteHost,
    required this.remotePort,
    Backoff? backoff,
  })  : _connect = connect,
        _backoff = backoff ?? Backoff();

  final Future<SshConnection> Function() _connect;
  final String remoteHost;
  final int remotePort;
  final Backoff _backoff;

  final _stateController = StreamController<TunnelState>.broadcast();

  ServerSocket? _server;
  SshConnection? _ssh;
  bool _closed = false;
  StreamSubscription<Socket>? _acceptSub;

  /// Поток изменений состояния туннеля.
  Stream<TunnelState> get states => _stateController.stream;

  /// Локальный порт, на котором слушает туннель (доступен после [start]).
  int get localPort => _server?.port ?? 0;

  /// Локальный базовый URL для control-API клиента.
  Uri get localBaseUri => Uri.parse('http://127.0.0.1:$localPort');

  /// Поднимает локальный слушающий сокет и устанавливает SSH-сессию.
  /// Возвращается, когда локальный порт готов принимать соединения.
  Future<void> start() async {
    if (_closed) {
      throw StateError('туннель уже закрыт');
    }
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _acceptSub = _server!.listen(_handleLocalConnection);
    await _establish();
  }

  void _emit(TunnelState state) {
    if (!_stateController.isClosed) _stateController.add(state);
  }

  /// Устанавливает SSH-сессию и вешает наблюдение за её обрывом.
  Future<void> _establish() async {
    if (_closed) return;
    _emit(TunnelState.connecting);
    try {
      final ssh = await _connect();
      _ssh = ssh;
      _backoff.reset();
      _emit(TunnelState.connected);
      // Наблюдаем за обрывом сессии, не блокируя start().
      unawaited(_watchDisconnect(ssh));
    } catch (_) {
      // Не удалось подключиться — уходим в цикл переподключения.
      await _scheduleReconnect();
    }
  }

  /// Ждёт закрытия SSH-сессии и, если туннель не закрыт намеренно,
  /// запускает переподключение.
  Future<void> _watchDisconnect(SshConnection ssh) async {
    await ssh.done;
    if (_closed || !identical(_ssh, ssh)) return;
    _ssh = null;
    await _scheduleReconnect();
  }

  Future<void> _scheduleReconnect() async {
    if (_closed) return;
    _emit(TunnelState.reconnecting);
    await Future<void>.delayed(_backoff.nextDelay());
    await _establish();
  }

  /// Пробрасывает входящее локальное соединение в канал к агенту.
  Future<void> _handleLocalConnection(Socket local) async {
    final ssh = _ssh;
    if (ssh == null || ssh.isClosed) {
      // SSH сейчас недоступен — рвём локальное соединение, HTTP-клиент повторит.
      await local.close();
      return;
    }
    try {
      final channel = await ssh.forwardLocal(remoteHost, remotePort);
      _bridge(local, channel);
    } catch (_) {
      await local.close();
    }
  }

  /// Двунаправленный обмен байтами между локальным сокетом и SSH-каналом.
  void _bridge(Socket local, SSHForwardChannel channel) {
    // local → канал
    local.listen(
      channel.sink.add,
      onDone: () => channel.sink.close(),
      onError: (_) => channel.sink.close(),
      cancelOnError: true,
    );
    // канал → local
    channel.stream.listen(
      local.add,
      onDone: () => local.destroy(),
      onError: (_) => local.destroy(),
      cancelOnError: true,
    );
  }

  /// Закрывает туннель: локальный сокет и SSH-сессию. Идемпотентно.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _emit(TunnelState.closed);
    await _acceptSub?.cancel();
    await _server?.close();
    await _ssh?.close();
    await _stateController.close();
  }
}
