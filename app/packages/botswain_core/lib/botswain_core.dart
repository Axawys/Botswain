/// Ядро клиента Botswain: SSH, туннель, control-API клиент, секреты, модели.
///
/// Пакет не содержит UI. Он одинаково пригоден для desktop- и будущего
/// Android-клиента (см. docs/architecture.md).
library;

// Модели / DTO
export 'src/models/server_profile.dart';
export 'src/models/health_status.dart';
export 'src/models/api_error.dart';
export 'src/models/bot.dart';
export 'src/models/bot_metrics.dart';
export 'src/models/proxy_config.dart';

// Боты
export 'src/bots/bot_source.dart';
export 'src/bots/bot_log_session.dart';

// Секреты
export 'src/secrets/secrets_store.dart';
export 'src/secrets/secure_secrets_store.dart';

// SSH
export 'src/ssh/ssh_client.dart';

// Туннель
export 'src/tunnel/tunnel.dart';

// Control-API
export 'src/api/control_api_client.dart';

// Bootstrap
export 'src/bootstrap/bootstrap.dart';

// Утилиты
export 'src/util/backoff.dart';

// Оркестрация
export 'src/connection_manager.dart';

// Локальный режим
export 'src/local/local_docker.dart';
export 'src/local/local_agent_manager.dart';
