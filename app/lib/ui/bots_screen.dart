import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';

import 'create_bot_dialog.dart';

/// Экран списка ботов на сервере: создание, запуск/остановка/перезапуск, удаление.
///
/// Тонкий слой поверх [ConnectionManager.api] из botswain_core.
class BotsScreen extends StatefulWidget {
  const BotsScreen({super.key, required this.manager});

  final ConnectionManager manager;

  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends State<BotsScreen> {
  List<Bot>? _bots;
  bool _loading = false;
  String? _error;

  ControlApiClient get _api => widget.manager.api!;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bots = await _api.listBots();
      if (mounted) setState(() => _bots = bots);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Выполняет действие над ботом и обновляет список, показывая ошибки.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _refresh();
    } on ApiError catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('$e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createBot() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => CreateBotDialog(api: _api),
    );
    if (created == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Боты'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBot,
        icon: const Icon(Icons.add),
        label: const Text('Новый бот'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _bots == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _refresh, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final bots = _bots ?? const [];
    if (bots.isEmpty) {
      return const Center(child: Text('Ботов пока нет. Создайте первого.'));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        itemCount: bots.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _BotTile(
          bot: bots[i],
          onStart: () => _run(() => _api.startBot(bots[i].id)),
          onStop: () => _run(() => _api.stopBot(bots[i].id)),
          onRestart: () => _run(() => _api.restartBot(bots[i].id)),
          onDelete: () => _run(() => _api.deleteBot(bots[i].id)),
        ),
      ),
    );
  }
}

class _BotTile extends StatelessWidget {
  const _BotTile({
    required this.bot,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onDelete,
  });

  final Bot bot;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _statusDot(bot.status),
      title: Text(bot.name),
      subtitle: Text(
        '${bot.entrypoint} · ${bot.status} · '
        '${bot.limits.memoryMb}МБ / ${bot.limits.cpus} CPU',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'start':
              onStart();
            case 'stop':
              onStop();
            case 'restart':
              onRestart();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          if (!bot.isRunning)
            const PopupMenuItem(value: 'start', child: Text('Запустить')),
          if (bot.isRunning)
            const PopupMenuItem(value: 'stop', child: Text('Остановить')),
          const PopupMenuItem(value: 'restart', child: Text('Перезапустить')),
          const PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ],
      ),
    );
  }

  Widget _statusDot(String status) {
    final color = switch (status) {
      'running' => Colors.green,
      'restarting' => Colors.orange,
      'exited' || 'dead' => Colors.red,
      _ => Colors.grey,
    };
    return Icon(Icons.circle, size: 14, color: color);
  }
}
