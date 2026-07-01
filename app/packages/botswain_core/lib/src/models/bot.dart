import 'package:meta/meta.dart';

/// Лимиты ресурсов бота.
@immutable
class BotLimits {
  const BotLimits({required this.memoryMb, required this.cpus});

  final int memoryMb;
  final double cpus;

  Map<String, dynamic> toJson() => {'memory_mb': memoryMb, 'cpus': cpus};

  factory BotLimits.fromJson(Map<String, dynamic> json) => BotLimits(
        memoryMb: (json['memory_mb'] as num?)?.toInt() ?? 0,
        cpus: (json['cpus'] as num?)?.toDouble() ?? 0,
      );
}

/// Бот в представлении control-API (см. docs/control-api.md).
@immutable
class Bot {
  const Bot({
    required this.id,
    required this.name,
    required this.entrypoint,
    required this.status,
    required this.limits,
    required this.image,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String entrypoint;

  /// Зеркалит состояние Docker-контейнера:
  /// created | running | restarting | paused | exited | dead.
  final String status;

  final BotLimits limits;
  final String image;
  final String createdAt;

  bool get isRunning => status == 'running';

  factory Bot.fromJson(Map<String, dynamic> json) => Bot(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        entrypoint: json['entrypoint'] as String? ?? '',
        status: json['status'] as String? ?? 'unknown',
        limits: BotLimits.fromJson(
            (json['limits'] as Map?)?.cast<String, dynamic>() ?? const {}),
        image: json['image'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

/// Спецификация нового бота (часть `spec` в multipart-запросе создания).
///
/// [limits] опциональны: если не заданы, агент подставит дефолты.
@immutable
class BotSpec {
  const BotSpec({
    required this.name,
    required this.entrypoint,
    this.limits,
  });

  final String name;
  final String entrypoint;
  final BotLimits? limits;

  Map<String, dynamic> toJson() => {
        'name': name,
        'entrypoint': entrypoint,
        if (limits != null) 'limits': limits!.toJson(),
      };
}
