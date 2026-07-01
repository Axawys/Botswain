import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';

/// Секция управления egress-прокси.
///
/// Прокси задаются одним многострочным полем (по одному в строке) — это
/// выдерживает списки в сотни прокси без подвисаний. Плюс загрузка списка по
/// URL (обычно raw-txt с GitHub). Результаты проверки показываются отдельным
/// виртуализированным списком: зелёный — рабочий, красный — нет.
class ProxySection extends StatefulWidget {
  const ProxySection({
    super.key,
    required this.api,
    required this.secrets,
    required this.contextId,
  });

  final ControlApiClient api;
  final SecretsStore secrets;

  /// Ключ хранения (`local` или `ssh:<host>`).
  final String contextId;

  @override
  State<ProxySection> createState() => _ProxySectionState();
}

class _ProxySectionState extends State<ProxySection> {
  final _text = TextEditingController();
  final _url = TextEditingController();

  ProxyConfig? _result;
  bool _checking = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await widget.secrets.readProxies(widget.contextId);
    final url = await widget.secrets.readProxySource(widget.contextId);
    if (!mounted) return;
    setState(() {
      _text.text = saved.join('\n');
      _url.text = url ?? '';
    });
  }

  List<String> _urls() => parseProxyList(_text.text);

  Future<void> _loadFromUrl() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await fetchProxyList(url);
      await widget.secrets.saveProxySource(widget.contextId, url);
      if (!mounted) return;
      setState(() => _text.text = list.join('\n'));
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось загрузить список: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
              'По одному прокси в строке. Голый host:port считается socks5. '
              'Боты пойдут через первый рабочий.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // Загрузка по URL.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _url,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'URL списка (raw .txt)',
                      hintText: 'https://raw.githubusercontent.com/…/proxies.txt',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _loadFromUrl,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('Загрузить'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Список прокси одним полем.
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 14,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'socks5://user:pass@host:1080\n185.12.34.56:1080\n…',
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.orange)),
            ],

            const SizedBox(height: 12),
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

            if (_result != null) _results(context, _result!),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context, ProxyConfig cfg) {
    final theme = Theme.of(context);
    final okCount = cfg.results.where((r) => r.ok).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'Рабочих: $okCount из ${cfg.results.length}',
          style: theme.textTheme.bodyMedium,
        ),
        if (cfg.active != null)
          Text('Активен: ${cfg.active}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.green))
        else if (cfg.results.isNotEmpty)
          Text('Ни один прокси не отвечает',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange)),
        const SizedBox(height: 8),
        // Виртуализированный список — тянет сотни прокси без лагов.
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: cfg.results.length,
            itemBuilder: (_, i) {
              final r = cfg.results[i];
              final isActive = cfg.active == r.url;
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  r.ok ? Icons.check_circle : Icons.cancel,
                  color: r.ok ? Colors.green : Colors.red,
                  size: 18,
                ),
                title: Text(
                  r.url,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isActive
                    ? const Tooltip(
                        message: 'Активный прокси',
                        child: Icon(Icons.bolt, color: Colors.green, size: 18),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
