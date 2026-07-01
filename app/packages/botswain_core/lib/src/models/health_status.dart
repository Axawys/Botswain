import 'package:meta/meta.dart';

/// Ответ `GET /v0/health` (см. docs/control-api.md).
///
/// Незнакомые поля игнорируются — это допускается контрактом для
/// обратной совместимости.
@immutable
class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.version,
    required this.commit,
    required this.uptimeSeconds,
    required this.time,
  });

  /// `"ok"` — агент готов; `"not_ready"` — процесс жив, но не готов.
  final String status;
  final String version;
  final String commit;
  final int uptimeSeconds;

  /// Момент ответа агента (RFC3339, UTC).
  final DateTime? time;

  bool get isOk => status == 'ok';

  factory HealthStatus.fromJson(Map<String, dynamic> json) => HealthStatus(
        status: json['status'] as String? ?? 'unknown',
        version: json['version'] as String? ?? '',
        commit: json['commit'] as String? ?? '',
        uptimeSeconds: json['uptime_seconds'] as int? ?? 0,
        time: DateTime.tryParse(json['time'] as String? ?? ''),
      );
}
