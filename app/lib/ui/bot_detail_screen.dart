import 'dart:async';

import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';

import 'half_gauge.dart';

/// Экран одного бота: живые метрики CPU/RAM (снапшоты по опросу) и консоль
/// логов в реальном времени (WebSocket). Тонкий слой поверх [ControlApiClient].
class BotDetailScreen extends StatefulWidget {
  const BotDetailScreen({super.key, required this.api, required this.bot});

  final ControlApiClient api;
  final Bot bot;

  @override
  State<BotDetailScreen> createState() => _BotDetailScreenState();
}

enum _LogState { connecting, streaming, failed }

class _BotDetailScreenState extends State<BotDetailScreen> {
  static const _logCap = 20000;
  static const _pollInterval = Duration(seconds: 2);
  static const _logConnectTimeout = Duration(seconds: 8);

  BotMetrics? _metrics;
  String? _metricsError;

  Timer? _pollTimer;
  bool _polling = false;

  final _log = StringBuffer();
  final _logScroll = ScrollController();
  BotLogSession? _logSession;
  StreamSubscription<String>? _logSub;
  _LogState _logState = _LogState.connecting;
  String? _logError;

  @override
  void initState() {
    super.initState();
    _startMetrics();
    _startLogs();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logSub?.cancel();
    _logSession?.close();
    _logScroll.dispose();
    super.dispose();
  }

  void _startMetrics() {
    _poll(); // сразу, не дожидаясь первого тика
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (_polling) return; // опрос метрик занимает ~1с, не наслаиваем
    _polling = true;
    try {
      final m = await widget.api.getBotMetrics(widget.bot.id);
      if (!mounted) return;
      setState(() {
        _metrics = m;
        _metricsError = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _metricsError = e.message);
    } catch (e) {
      if (mounted) setState(() => _metricsError = '$e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _startLogs() async {
    final session = widget.api.connectBotLogs(widget.bot.id);
    _logSession = session;

    // Ждём рукопожатие с таймаутом: иначе при проблеме соединения экран
    // висел бы на «Подключение…» бесконечно.
    try {
      await session.ready.timeout(_logConnectTimeout);
    } catch (e) {
      if (mounted) {
        setState(() {
          _logState = _LogState.failed;
          _logError = 'не удалось подключиться к логам: $e';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _logState = _LogState.streaming);

    _logSub = session.chunks.listen(
      _appendLog,
      onError: (e) {
        if (mounted) {
          setState(() {
            _logState = _LogState.failed;
            _logError = 'поток логов прерван: $e';
          });
        }
      },
    );
  }

  void _appendLog(String chunk) {
    if (!mounted) return;
    setState(() {
      _log.write(chunk);
      // Ограничиваем буфер, чтобы не рос бесконечно.
      if (_log.length > _logCap) {
        final trimmed = _log.toString();
        _log
          ..clear()
          ..write(trimmed.substring(trimmed.length - _logCap));
      }
    });
    // Автопрокрутка вниз после отрисовки.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.bot.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _metricsCard(context),
            const SizedBox(height: 16),
            Text('Логи', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(child: _logConsole(context)),
          ],
        ),
      ),
    );
  }

  Widget _metricsCard(BuildContext context) {
    final m = _metrics;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_metricsError != null)
              Text(_metricsError!,
                  style: const TextStyle(color: Colors.orange))
            else if (m == null)
              const Text('Сбор метрик…')
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  HalfCircleGauge(
                    value: m.cpuPercent / 100,
                    centerText: '${m.cpuPercent.toStringAsFixed(0)}%',
                    caption: 'CPU',
                    color: scheme.primary,
                  ),
                  HalfCircleGauge(
                    value: m.memoryPercent / 100,
                    centerText: '${m.memoryPercent.toStringAsFixed(0)}%',
                    caption: 'RAM '
                        '${m.memoryUsedMb.toStringAsFixed(0)}/'
                        '${m.memoryLimitMb.toStringAsFixed(0)} МБ',
                    color: scheme.tertiary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.storage, size: 18, color: scheme.outline),
                  const SizedBox(width: 8),
                  Text('Диск: ${_formatDisk(m.diskUsedMb)}'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDisk(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} ГБ';
    return '${mb.toStringAsFixed(1)} МБ';
  }

  Widget _logConsole(BuildContext context) {
    final placeholder = switch (_logState) {
      _LogState.connecting => 'Подключение к логам…',
      _LogState.failed => _logError ?? 'Ошибка подключения к логам',
      _LogState.streaming => 'Ожидание вывода…',
    };
    final showPlaceholder = _log.isEmpty || _logState != _LogState.streaming;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        controller: _logScroll,
        child: SelectableText(
          showPlaceholder ? placeholder : _log.toString(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
