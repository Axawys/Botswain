import 'dart:async';

import 'package:botswain_core/botswain_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Экран одного бота: живые метрики CPU/RAM (снапшоты по опросу) и консоль
/// логов в реальном времени (WebSocket). Тонкий слой поверх [ControlApiClient].
class BotDetailScreen extends StatefulWidget {
  const BotDetailScreen({super.key, required this.api, required this.bot});

  final ControlApiClient api;
  final Bot bot;

  @override
  State<BotDetailScreen> createState() => _BotDetailScreenState();
}

class _BotDetailScreenState extends State<BotDetailScreen> {
  static const _historyLen = 60;
  static const _logCap = 20000;
  static const _pollInterval = Duration(seconds: 2);

  final _cpuHistory = <double>[];
  final _memHistory = <double>[];
  BotMetrics? _metrics;
  String? _metricsError;

  Timer? _pollTimer;
  bool _polling = false;

  final _log = StringBuffer();
  final _logScroll = ScrollController();
  BotLogSession? _logSession;
  StreamSubscription<String>? _logSub;

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
        _push(_cpuHistory, m.cpuPercent);
        _push(_memHistory, m.memoryPercent);
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _metricsError = e.message);
    } catch (e) {
      if (mounted) setState(() => _metricsError = '$e');
    } finally {
      _polling = false;
    }
  }

  void _push(List<double> buf, double v) {
    buf.add(v);
    if (buf.length > _historyLen) buf.removeAt(0);
  }

  void _startLogs() {
    final session = widget.api.connectBotLogs(widget.bot.id);
    _logSession = session;
    _logSub = session.chunks.listen(
      _appendLog,
      onError: (_) => _appendLog('\n[поток логов прерван]\n'),
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
              Text('CPU: ${m.cpuPercent.toStringAsFixed(1)}%'),
              const SizedBox(height: 4),
              SizedBox(height: 60, child: _sparkline(context, _cpuHistory)),
              const SizedBox(height: 12),
              Text('RAM: ${m.memoryUsedMb.toStringAsFixed(1)} / '
                  '${m.memoryLimitMb.toStringAsFixed(0)} МБ '
                  '(${m.memoryPercent.toStringAsFixed(1)}%)'),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (m.memoryPercent / 100).clamp(0, 1),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sparkline(BuildContext context, List<double> data) {
    if (data.length < 2) {
      return const Center(child: Text('…'));
    }
    final spots = [
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i]),
    ];
    final color = Theme.of(context).colorScheme.primary;
    return LineChart(
      LineChartData(
        minY: 0,
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logConsole(BuildContext context) {
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
          _log.isEmpty ? 'Ожидание логов…' : _log.toString(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
