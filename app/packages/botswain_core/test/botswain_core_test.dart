import 'dart:math';

import 'package:botswain_core/botswain_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Backoff', () {
    test('растёт экспоненциально и упирается в потолок', () {
      // jitter=0 → детерминированно.
      final bo = Backoff(
        initial: const Duration(milliseconds: 100),
        max: const Duration(milliseconds: 800),
        factor: 2,
        jitter: 0,
        random: Random(1),
      );

      expect(bo.nextDelay().inMilliseconds, 100);
      expect(bo.nextDelay().inMilliseconds, 200);
      expect(bo.nextDelay().inMilliseconds, 400);
      expect(bo.nextDelay().inMilliseconds, 800);
      // Потолок держится.
      expect(bo.nextDelay().inMilliseconds, 800);
    });

    test('reset возвращает к начальной задержке', () {
      final bo = Backoff(
        initial: const Duration(milliseconds: 100),
        factor: 2,
        jitter: 0,
        random: Random(1),
      );
      bo.nextDelay();
      bo.nextDelay();
      bo.reset();
      expect(bo.nextDelay().inMilliseconds, 100);
    });
  });

  group('ApiError', () {
    test('разбирает конверт ошибки', () {
      final err = ApiError.fromJson(
        {
          'error': {'code': 'not_ready', 'message': 'wait'}
        },
        httpStatus: 503,
      );
      expect(err.code, 'not_ready');
      expect(err.message, 'wait');
      expect(err.httpStatus, 503);
    });

    test('на мусорном теле не падает, а даёт malformed_error', () {
      final err = ApiError.fromJson({'nonsense': 1}, httpStatus: 500);
      expect(err.code, 'malformed_error');
    });
  });

  group('HealthStatus', () {
    test('isOk true только при status=ok', () {
      final ok = HealthStatus.fromJson({'status': 'ok', 'version': '0.1.0'});
      expect(ok.isOk, isTrue);
      final notReady = HealthStatus.fromJson({'status': 'not_ready'});
      expect(notReady.isOk, isFalse);
    });

    test('игнорирует незнакомые поля', () {
      final h = HealthStatus.fromJson({
        'status': 'ok',
        'version': '0.1.0',
        'future_field': 'ignored',
      });
      expect(h.status, 'ok');
    });
  });

  group('ServerProfile', () {
    test('round-trip через JSON', () {
      const p = ServerProfile(
        id: 'srv1',
        host: '10.0.0.1',
        port: 22,
        username: 'root',
        agentPort: 8080,
      );
      final restored = ServerProfile.fromJson(p.toJson());
      expect(restored.host, p.host);
      expect(restored.agentPort, 8080);
    });
  });
}
