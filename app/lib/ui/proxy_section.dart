import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';

/// Секция управления egress-прокси: список полей, проверка и индикаторы.
///
/// Первый рабочий прокси агент выбирает активным (через него идут новые боты).
/// Зелёный индикатор — прокси отвечает, красный — нет, серый — ещё не проверяли.
class ProxySection extends StatefulWidget {
  const ProxySection({
    super.key,
    required this.api,
    required this.secrets,
    required this.contextId,
  });

  final ControlApiClient api;
  final SecretsStore secrets;

  /// Ключ хранения списка прокси (`local` или `ssh:<host>`).
  final String contextId;

  @override
  State<ProxySection> createState() => _ProxySectionState();
}

class _ProxySectionState extends State<ProxySection> {
  final List<TextEditingController> _controllers = [];
  ProxyConfig? _result;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await widget.secrets.readProxies(widget.contextId);
    setState(() {
      _controllers
        ..clear()
        ..addAll(
          (saved.isEmpty ? [''] : saved)
              .map((s) => TextEditingController(text: s)),
        );
    });
  }

  void _addField() {
    setState(() => _controllers.add(TextEditingController()));
  }

  void _removeField(int i) {
    setState(() {
      _controllers.removeAt(i).dispose();
      if (_controllers.isEmpty) _controllers.add(TextEditingController());
    });
  }

  List<String> _urls() => _controllers
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _check() async {
    final urls = _urls();
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.secrets.saveProxies(widget.contextId, urls);
      final cfg = await widget.api.setProxies(urls);
      if (mounted) setState(() => _result = cfg);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Egress-прокси к Telegram', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Боты пойдут через первый рабочий прокси. '
              'Схемы: http, https, socks5.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _controllers.length; i++) _proxyRow(i),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addField,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить прокси'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: Colors.orange)),
            ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _checking ? null : _check,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: const Text('Проверить прокси'),
            ),
            if (_result?.active != null) ...[
              const SizedBox(height: 8),
              Text(
                'Активен: ${_result!.active}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.green),
              ),
            ] else if (_result != null && _result!.results.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Ни один прокси не отвечает',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.orange)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _proxyRow(int i) {
    final url = _controllers[i].text.trim();
    final status = url.isEmpty ? null : _result?.statusFor(url);
    final isActive = _result?.active != null && _result!.active == url;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _indicator(status),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controllers[i],
              decoration: InputDecoration(
                isDense: true,
                hintText: 'socks5://user:pass@host:1080',
                border: const OutlineInputBorder(),
                suffixIcon: isActive
                    ? const Tooltip(
                        message: 'Активный прокси',
                        child: Icon(Icons.bolt, color: Colors.green, size: 18),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            onPressed: () => _removeField(i),
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Удалить',
          ),
        ],
      ),
    );
  }

  Widget _indicator(bool? status) {
    final (icon, color) = switch (status) {
      true => (Icons.check_circle, Colors.green),
      false => (Icons.cancel, Colors.red),
      null => (Icons.circle_outlined, Colors.grey),
    };
    return Icon(icon, color: color, size: 18);
  }
}
