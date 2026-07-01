import 'package:meta/meta.dart';

/// Ошибка control-API в едином формате конверта (см. docs/control-api.md):
/// `{"error":{"code":..., "message":..., "details":...}}`.
@immutable
class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.message,
    this.details,
    this.httpStatus,
  });

  /// Стабильный машиночитаемый код (`snake_case`). Клиент ветвится по нему.
  final String code;

  /// Человекочитаемое сообщение — для логов, не для парсинга.
  final String message;

  final Map<String, dynamic>? details;

  /// HTTP-статус ответа, если ошибка получена из HTTP-слоя.
  final int? httpStatus;

  /// Разбирает тело ошибки. Если тело не в формате конверта — возвращает
  /// ошибку с кодом `malformed_error`, чтобы клиент не падал на мусоре.
  factory ApiError.fromJson(Map<String, dynamic> json, {int? httpStatus}) {
    final err = json['error'];
    if (err is Map<String, dynamic>) {
      return ApiError(
        code: err['code'] as String? ?? 'unknown',
        message: err['message'] as String? ?? '',
        details: (err['details'] as Map?)?.cast<String, dynamic>(),
        httpStatus: httpStatus,
      );
    }
    return ApiError(
      code: 'malformed_error',
      message: 'unexpected error body',
      httpStatus: httpStatus,
    );
  }

  @override
  String toString() => 'ApiError($code, http=$httpStatus): $message';
}
