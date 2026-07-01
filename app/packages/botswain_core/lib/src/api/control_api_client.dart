import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../bots/bot_source.dart';
import '../models/api_error.dart';
import '../models/bot.dart';
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

  // --- Боты (M2) ---

  /// `GET /v0/bots` — список ботов.
  Future<List<Bot>> listBots() async {
    final resp = await _http.get(_uri('/bots'));
    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is List) {
        return decoded
            .map((e) => Bot.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
      return const [];
    }
    throw ApiError.fromJson(_decodeBody(resp), httpStatus: resp.statusCode);
  }

  /// `GET /v0/bots/{id}` — один бот.
  Future<Bot> getBot(String id) async {
    final resp = await _http.get(_uri('/bots/$id'));
    if (resp.statusCode == 200) return Bot.fromJson(_decodeBody(resp));
    throw ApiError.fromJson(_decodeBody(resp), httpStatus: resp.statusCode);
  }

  /// `POST /v0/bots` — создать и запустить бота. Файлы упаковываются в `.tar.gz`
  /// и отправляются вместе со спеком как multipart.
  Future<Bot> createBot(BotSpec spec, List<BotSourceFile> files) async {
    final req = http.MultipartRequest('POST', _uri('/bots'));
    req.fields['spec'] = jsonEncode(spec.toJson());
    req.files.add(http.MultipartFile.fromBytes(
      'code',
      packBotArchive(files),
      filename: 'code.tar.gz',
    ));

    final resp = await http.Response.fromStream(await _http.send(req));
    if (resp.statusCode == 201) return Bot.fromJson(_decodeBody(resp));
    throw ApiError.fromJson(_decodeBody(resp), httpStatus: resp.statusCode);
  }

  /// `POST /v0/bots/{id}/start`.
  Future<Bot> startBot(String id) => _lifecycle(id, 'start');

  /// `POST /v0/bots/{id}/stop`.
  Future<Bot> stopBot(String id) => _lifecycle(id, 'stop');

  /// `POST /v0/bots/{id}/restart`.
  Future<Bot> restartBot(String id) => _lifecycle(id, 'restart');

  Future<Bot> _lifecycle(String id, String action) async {
    final resp = await _http.post(_uri('/bots/$id/$action'));
    if (resp.statusCode == 200) return Bot.fromJson(_decodeBody(resp));
    throw ApiError.fromJson(_decodeBody(resp), httpStatus: resp.statusCode);
  }

  /// `DELETE /v0/bots/{id}` — удалить контейнер и volume бота.
  Future<void> deleteBot(String id) async {
    final resp = await _http.delete(_uri('/bots/$id'));
    if (resp.statusCode == 204) return;
    throw ApiError.fromJson(_decodeBody(resp), httpStatus: resp.statusCode);
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
