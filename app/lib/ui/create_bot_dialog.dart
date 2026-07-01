import 'package:botswain_core/botswain_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Диалог создания бота: имя, python-файл, опциональный requirements.txt,
/// лимиты ресурсов. Возвращает `true` через Navigator при успешном создании.
class CreateBotDialog extends StatefulWidget {
  const CreateBotDialog({super.key, required this.api});

  final ControlApiClient api;

  @override
  State<CreateBotDialog> createState() => _CreateBotDialogState();
}

class _CreateBotDialogState extends State<CreateBotDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _memoryMb = TextEditingController(text: '256');
  final _cpus = TextEditingController(text: '0.5');

  PlatformFile? _entryFile;
  PlatformFile? _requirementsFile;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _memoryMb.dispose();
    _cpus.dispose();
    super.dispose();
  }

  Future<void> _pickEntry() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['py'],
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _entryFile = res.files.single);
    }
  }

  Future<void> _pickRequirements() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res != null && res.files.isNotEmpty) {
      setState(() => _requirementsFile = res.files.single);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_entryFile?.bytes == null) {
      setState(() => _error = 'Выберите python-файл бота');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    // entrypoint — имя выбранного файла; он ложится в корень архива.
    final entrypoint = _entryFile!.name;
    final files = <BotSourceFile>[
      BotSourceFile(name: entrypoint, bytes: _entryFile!.bytes!),
      if (_requirementsFile?.bytes != null)
        // Имя фиксируем — агент ищет именно requirements.txt в корне.
        BotSourceFile(name: 'requirements.txt', bytes: _requirementsFile!.bytes!),
    ];

    final spec = BotSpec(
      name: _name.text.trim(),
      entrypoint: entrypoint,
      limits: BotLimits(
        memoryMb: int.parse(_memoryMb.text.trim()),
        cpus: double.parse(_cpus.text.trim()),
      ),
    );

    try {
      await widget.api.createBot(spec, files);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый бот'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Имя бота'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
              ),
              const SizedBox(height: 12),
              _filePickRow(
                label: _entryFile?.name ?? 'Python-файл не выбран',
                buttonText: 'Выбрать .py',
                onPick: _pickEntry,
              ),
              _filePickRow(
                label: _requirementsFile?.name ??
                    'requirements.txt (необязательно)',
                buttonText: 'Выбрать',
                onPick: _pickRequirements,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _memoryMb,
                      decoration:
                          const InputDecoration(labelText: 'Память, МБ'),
                      keyboardType: TextInputType.number,
                      validator: _positiveInt,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cpus,
                      decoration: const InputDecoration(labelText: 'CPU (доля)'),
                      keyboardType: TextInputType.number,
                      validator: _positiveDouble,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }

  Widget _filePickRow({
    required String label,
    required String buttonText,
    required VoidCallback onPick,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onPick, child: Text(buttonText)),
        ],
      ),
    );
  }

  String? _positiveInt(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return '> 0';
    return null;
  }

  String? _positiveDouble(String? v) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return '> 0';
    return null;
  }
}
