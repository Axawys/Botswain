import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'bots_screen.dart';
import 'connection_status_view.dart';

/// Вкладка «SSH»: ip/login/password → bootstrap агента на VPS → туннель →
/// health. Плюс отзыв агента. Тонкий слой поверх [ConnectionManager].
class SshTab extends StatefulWidget {
  const SshTab({super.key, required this.secrets});

  final SecretsStore secrets;

  @override
  State<SshTab> createState() => _SshTabState();
}

class _SshTabState extends State<SshTab> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController(text: 'root');
  final _password = TextEditingController();
  final _agentPort = TextEditingController(text: '8080');

  ConnectionManager? _manager;
  bool _connecting = false;
  bool _revoking = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _agentPort.dispose();
    _manager?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    await _manager?.dispose();

    final profile = ServerProfile(
      id: const Uuid().v4(),
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _username.text.trim(),
      agentPort: int.parse(_agentPort.text.trim()),
    );

    // Секреты — только в защищённое хранилище, никогда в конфиг.
    await widget.secrets.saveSshCredentials(
      profile.id,
      SshCredentials(password: _password.text),
    );

    final manager = ConnectionManager(profile: profile, secrets: widget.secrets);
    setState(() {
      _manager = manager;
      _connecting = true;
    });

    try {
      await manager.connect();
    } catch (_) {
      // Итоговый статус эмитит менеджер, он виден в ConnectionStatusView.
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _revoke() async {
    final manager = _manager;
    if (manager == null) return;
    setState(() => _revoking = true);
    try {
      await manager.revokeAgent();
      if (mounted) setState(() => _manager = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отозвать агента: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _host,
                      decoration: const InputDecoration(
                        labelText: 'IP или хост',
                        hintText: '203.0.113.10',
                      ),
                      validator: _required,
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _username,
                            decoration:
                                const InputDecoration(labelText: 'Логин SSH'),
                            validator: _required,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _port,
                            decoration:
                                const InputDecoration(labelText: 'Порт SSH'),
                            keyboardType: TextInputType.number,
                            validator: _portValidator,
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _password,
                      decoration:
                          const InputDecoration(labelText: 'Пароль SSH'),
                      obscureText: true,
                      validator: _required,
                    ),
                    TextFormField(
                      controller: _agentPort,
                      decoration: const InputDecoration(
                        labelText: 'Порт агента',
                        helperText: 'Loopback-порт агента на сервере',
                      ),
                      keyboardType: TextInputType.number,
                      validator: _portValidator,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _connecting ? null : _connect,
                      icon: _connecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link),
                      label: Text(_connecting
                          ? 'Подключение…'
                          : 'Подключиться и поднять агента'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_manager != null) ...[
                ConnectionStatusView(manager: _manager!),
                const SizedBox(height: 12),
                StreamBuilder<ConnectionStatus>(
                  stream: _manager!.statuses,
                  initialData: _manager!.status,
                  builder: (context, snapshot) {
                    final healthy =
                        snapshot.data?.phase == ConnectionPhase.healthy;
                    if (!healthy) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  BotsScreen(api: _manager!.api!),
                            ),
                          ),
                          icon: const Icon(Icons.smart_toy_outlined),
                          label: const Text('Управление ботами'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _revoking ? null : _revoke,
                          icon: _revoking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.power_settings_new),
                          label: const Text('Отозвать агента'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null;

  String? _portValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Обязательное поле';
    final n = int.tryParse(v.trim());
    if (n == null || n < 1 || n > 65535) return 'Порт 1–65535';
    return null;
  }
}
