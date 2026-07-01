import 'dart:math';

/// Экспоненциальный backoff с джиттером.
///
/// Используется и туннелем (переподключение SSH), и health-поллером. Заложен
/// с самого начала: устойчивость к разрыву туннеля дешевле встроить сразу.
class Backoff {
  Backoff({
    this.initial = const Duration(milliseconds: 500),
    this.max = const Duration(seconds: 5),
    this.factor = 2.0,
    this.jitter = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  final Duration initial;
  final Duration max;
  final double factor;

  /// Доля случайного разброса (0..1), чтобы клиенты не переподключались синхронно.
  final double jitter;

  final Random _random;
  int _attempt = 0;

  /// Сбрасывает счётчик после успешного подключения.
  void reset() => _attempt = 0;

  /// Возвращает задержку перед следующей попыткой и увеличивает счётчик.
  Duration nextDelay() {
    final base = initial.inMilliseconds * pow(factor, _attempt);
    final capped = min(base, max.inMilliseconds.toDouble());
    final rand = 1 + (_random.nextDouble() * 2 - 1) * jitter;
    _attempt++;
    return Duration(milliseconds: (capped * rand).round());
  }
}
