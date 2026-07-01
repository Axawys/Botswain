import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Один файл исходников бота (например `main.py` или `requirements.txt`).
class BotSourceFile {
  const BotSourceFile({required this.name, required this.bytes});

  /// Имя файла в корне архива (без путей).
  final String name;
  final List<int> bytes;
}

/// Упаковывает файлы бота в `.tar.gz` для отправки агенту.
///
/// Агент распакует архив в per-bot volume; `entrypoint` и опциональный
/// `requirements.txt` должны лежать в корне (см. docs/control-api.md).
Uint8List packBotArchive(List<BotSourceFile> files) {
  final archive = Archive();
  for (final f in files) {
    archive.addFile(ArchiveFile(f.name, f.bytes.length, f.bytes));
  }
  final tar = TarEncoder().encode(archive);
  final gz = GZipEncoder().encode(tar);
  return Uint8List.fromList(gz);
}
