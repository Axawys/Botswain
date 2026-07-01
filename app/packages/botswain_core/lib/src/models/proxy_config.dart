import 'package:meta/meta.dart';

/// Результат проверки одного прокси.
@immutable
class ProxyStatus {
  const ProxyStatus({required this.url, required this.ok});

  final String url;
  final bool ok;

  factory ProxyStatus.fromJson(Map<String, dynamic> json) => ProxyStatus(
        url: json['url'] as String? ?? '',
        ok: json['ok'] as bool? ?? false,
      );
}

/// Конфигурация egress-прокси: результаты проверки и активный прокси
/// (первый рабочий). См. docs/control-api.md.
@immutable
class ProxyConfig {
  const ProxyConfig({required this.results, this.active});

  final List<ProxyStatus> results;

  /// Активный прокси (первый рабочий) или `null`.
  final String? active;

  factory ProxyConfig.fromJson(Map<String, dynamic> json) => ProxyConfig(
        results: ((json['results'] as List?) ?? const [])
            .map((e) => ProxyStatus.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        active: json['active'] as String?,
      );

  /// Статус конкретного url из последней проверки (или `null`, если не проверялся).
  bool? statusFor(String url) {
    for (final r in results) {
      if (r.url == url) return r.ok;
    }
    return null;
  }
}
