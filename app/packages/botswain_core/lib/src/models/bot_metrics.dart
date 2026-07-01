import 'package:meta/meta.dart';

/// Снапшот потребления ресурсов ботом (см. docs/control-api.md).
@immutable
class BotMetrics {
  const BotMetrics({
    required this.cpuPercent,
    required this.memoryUsedMb,
    required this.memoryLimitMb,
    required this.memoryPercent,
  });

  /// Доля CPU в процентах (100 = одно полное ядро).
  final double cpuPercent;
  final double memoryUsedMb;
  final double memoryLimitMb;
  final double memoryPercent;

  factory BotMetrics.fromJson(Map<String, dynamic> json) => BotMetrics(
        cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0,
        memoryUsedMb: (json['memory_used_mb'] as num?)?.toDouble() ?? 0,
        memoryLimitMb: (json['memory_limit_mb'] as num?)?.toDouble() ?? 0,
        memoryPercent: (json['memory_percent'] as num?)?.toDouble() ?? 0,
      );
}
