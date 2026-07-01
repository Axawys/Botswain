import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Живая сессия логов бота поверх WebSocket.
///
/// Обёртка скрывает от UI детали web_socket_channel: наружу — поток строк и
/// метод закрытия. Транспорт — тот же SSH-туннель, что и для HTTP.
class BotLogSession {
  BotLogSession(this._channel);

  final WebSocketChannel _channel;

  /// Поток текстовых фрагментов логов. Фрагмент может содержать несколько
  /// строк или часть строки — потребитель просто дописывает его в консоль.
  Stream<String> get chunks => _channel.stream.map((event) {
        if (event is String) return event;
        if (event is List<int>) return utf8.decode(event);
        return event.toString();
      });

  /// Закрывает соединение (агент прекратит следовать за логами).
  Future<void> close() => _channel.sink.close();
}
