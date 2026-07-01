import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';

/// Отображает текущую фазу подключения из [ConnectionManager], включая
/// финальную индикацию «агент жив» и состояние переподключения туннеля.
class ConnectionStatusView extends StatelessWidget {
  const ConnectionStatusView({super.key, required this.manager});

  final ConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatus>(
      stream: manager.statuses,
      initialData: manager.status,
      builder: (context, snapshot) {
        final status = snapshot.data!;
        final view = _describe(status.phase);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _indicator(view),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        view.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                if (status.message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    status.message!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (status.health != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'agent ${status.health!.version} · commit '
                    '${status.health!.commit} · uptime '
                    '${status.health!.uptimeSeconds}s',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _indicator(_PhaseView view) {
    if (view.spinning) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(view.icon, color: view.color, size: 20);
  }

  _PhaseView _describe(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.idle:
        return const _PhaseView('Готово к подключению', Icons.circle_outlined,
            Colors.grey, false);
      case ConnectionPhase.connecting:
        return const _PhaseView('Подключение по SSH…', null, null, true);
      case ConnectionPhase.checkingDocker:
        return const _PhaseView('Проверка Docker…', null, null, true);
      case ConnectionPhase.dockerMissing:
        return const _PhaseView(
            'Docker не установлен', Icons.error_outline, Colors.orange, false);
      case ConnectionPhase.startingAgent:
        return const _PhaseView('Запуск агента…', null, null, true);
      case ConnectionPhase.openingTunnel:
        return const _PhaseView('Поднятие туннеля…', null, null, true);
      case ConnectionPhase.waitingHealth:
        return const _PhaseView('Ожидание ответа агента…', null, null, true);
      case ConnectionPhase.healthy:
        return const _PhaseView(
            'Агент жив', Icons.check_circle, Colors.green, false);
      case ConnectionPhase.reconnecting:
        return const _PhaseView('Переподключение туннеля…',
            Icons.sync_problem, Colors.orange, false);
      case ConnectionPhase.failed:
        return const _PhaseView(
            'Ошибка подключения', Icons.cancel, Colors.red, false);
    }
  }
}

class _PhaseView {
  const _PhaseView(this.label, this.icon, this.color, this.spinning);
  final String label;
  final IconData? icon;
  final Color? color;
  final bool spinning;
}
