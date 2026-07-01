import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'bots_screen.dart';
import 'connection_status_view.dart';

/// Экран «добавить сервер»: ip/login/password → подключение к агенту.
///
/// Тонкий UI-слой поверх [ConnectionManager] из botswain_core: вся логика
/// (SSH, bootstrap, туннель, health) — в ядре.
class AddServerScreen extends StatefulWidget {
  const AddServerScreen({super.key, required this.secrets});

  final SecretsStore secrets;

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController(text: 'root');
  final _password = TextEditingController();
  final _agentPort = TextEditingController(text: '8080');

  ConnectionManager? _manager;
  bool _connecting = false;

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

    // Закрываем предыдущее подключение, если было.
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
      // Финальный статус (failed/dockerMissing) уже эмитится менеджером и
      // отображается в ConnectionStatusView — отдельная обработка не нужна.
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Botswain — подключение к серверу')),
      body: Center(
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                  // Кнопка управления ботами появляется, когда агент жив.
                  StreamBuilder<ConnectionStatus>(
                    stream: _manager!.statuses,
                    initialData: _manager!.status,
                    builder: (context, snapshot) {
                      final healthy =
                          snapshot.data?.phase == ConnectionPhase.healthy;
                      if (!healthy) return const SizedBox.shrink();
                      return FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BotsScreen(manager: _manager!),
                          ),
                        ),
                        icon: const Icon(Icons.smart_toy_outlined),
                        label: const Text('Управление ботами'),
                      );
                    },
                  ),
                ],
              ],
            ),
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
