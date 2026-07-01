import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';

import 'bots_screen.dart';

/// Вкладка «Локально»: агент поднимается прямо на ПК пользователя, без SSH и
/// туннеля. Активировать → сразу запускать ботов локально; отозвать — убрать
/// агента.
class LocalTab extends StatefulWidget {
  const LocalTab({super.key});

  @override
  State<LocalTab> createState() => _LocalTabState();
}

class _LocalTabState extends State<LocalTab> {
  final _manager = LocalAgentManager();
  bool _busy = false;

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    try {
      await _manager.activate();
    } catch (_) {
      // Итоговый статус уже в потоке statuses и отображается ниже.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    setState(() => _busy = true);
    try {
      await _manager.deactivate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отозвать агента: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: StreamBuilder<LocalAgentStatus>(
            stream: _manager.statuses,
            initialData: _manager.status,
            builder: (context, snapshot) {
              final status = snapshot.data!;
              final active = status.isActive;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Локальный режим',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Агент запускается на этом ПК через локальный Docker — без '
                    'SSH и настройки сервера. Требуется установленный Docker и '
                    'собранный образ агента.',
                  ),
                  const SizedBox(height: 20),
                  if (!active)
                    FilledButton.icon(
                      onPressed: _busy ? null : _activate,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Активировать агента локально'),
                    ),
                  const SizedBox(height: 16),
                  _statusCard(context, status),
                  if (active) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BotsScreen(api: _manager.api!),
                        ),
                      ),
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: const Text('Управление ботами'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _revoke,
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('Отозвать агента'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context, LocalAgentStatus status) {
    final (label, icon, color, spinning) = _describe(status.phase);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (spinning)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Text(label, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            if (status.message != null) ...[
              const SizedBox(height: 8),
              Text(status.message!,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (status.health != null) ...[
              const SizedBox(height: 8),
              Text(
                'agent ${status.health!.version} · commit '
                '${status.health!.commit}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  (String, IconData, Color, bool) _describe(LocalAgentPhase phase) {
    return switch (phase) {
      LocalAgentPhase.idle =>
        ('Агент не активирован', Icons.circle_outlined, Colors.grey, false),
      LocalAgentPhase.checkingDocker =>
        ('Проверка Docker…', Icons.circle_outlined, Colors.grey, true),
      LocalAgentPhase.dockerMissing =>
        ('Docker недоступен', Icons.error_outline, Colors.orange, false),
      LocalAgentPhase.imageMissing =>
        ('Нет образа агента', Icons.error_outline, Colors.orange, false),
      LocalAgentPhase.startingAgent =>
        ('Запуск агента…', Icons.circle_outlined, Colors.grey, true),
      LocalAgentPhase.waitingHealth =>
        ('Ожидание ответа агента…', Icons.circle_outlined, Colors.grey, true),
      LocalAgentPhase.healthy =>
        ('Агент жив', Icons.check_circle, Colors.green, false),
      LocalAgentPhase.failed =>
        ('Ошибка активации', Icons.cancel, Colors.red, false),
    };
  }
}
