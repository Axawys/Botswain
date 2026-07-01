import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_error.dart';
import '../models/health_status.dart';
import '../util/backoff.dart';

/// Клиент control-API агента (см. docs/control-api.md).
///
/// Работает поверх любого транспорта: [baseUri] указывает либо на локальный
/// порт SSH-туннеля, либо напрямую на агента в локальном режиме — код клиента
/// одинаков.
class ControlApiClient {
  ControlApiClient({required this.baseUri, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final Uri baseUri;
  final http.Client _http;

  static const _apiPrefix = '/v0';

  /// `GET /v0/health`. Бросает [ApiError] на не-2xx и на нечитаемое тело.
  Future<HealthStatus> health() async {
    final resp = await _http.get(_uri('/health'));
    final body = _decodeBody(resp);
    if (resp.statusCode == 200) {
      return HealthStatus.fromJson(body);
    }
    throw ApiError.fromJson(body, httpStatus: resp.statusCode);
  }

  /// Опрашивает `/v0/health` с backoff, пока не получит `status == ok` или
  /// не истечёт [timeout]. Используется при bootstrap и после переподключения
  /// туннеля. Возвращает первый успешный [HealthStatus].
  Future<HealthStatus> waitUntilHealthy({
    Duration timeout = const Duration(seconds: 30),
    Backoff? backoff,
  }) async {
    final bo = backoff ?? Backoff();
    final deadline = DateTime.now().add(timeout);

    while (true) {
      try {
        final status = await health();
        if (status.isOk) return status;
      } catch (_) {
        // Агент ещё не поднялся или туннель не готов — продолжаем ждать.
      }
      final delay = bo.nextDelay();
      if (DateTime.now().add(delay).isAfter(deadline)) {
        throw TimeoutException(
          'агент не ответил health=ok за $timeout',
        );
      }
      await Future<void>.delayed(delay);
    }
  }

  Uri _uri(String path) => baseUri.replace(path: '$_apiPrefix$path');

  /// Разбирает JSON-тело; при мусоре возвращает пустую карту, чтобы
  /// вызывающий код мог отдать осмысленную [ApiError] вместо падения.
  Map<String, dynamic> _decodeBody(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // ниже вернём пустую карту
    }
    return const {};
  }

  void close() => _http.close();
}
