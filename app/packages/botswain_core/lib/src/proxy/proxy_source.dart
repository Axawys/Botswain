import 'package:http/http.dart' as http;

/// Скачивает список прокси по URL (обычно raw-txt с GitHub) и разбирает его
/// построчно. Качает само приложение — это просто загрузка текста; доступность
/// прокси всё равно проверяет агент из своей сети.
///
/// Пустые строки и комментарии (`#`) игнорируются. Возвращает строки как есть —
/// нормализацию схемы (`socks5://` для голого `host:port`) делает агент.
Future<List<String>> fetchProxyList(String url, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final resp = await c.get(Uri.parse(url)).timeout(
          const Duration(seconds: 15),
        );
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} при загрузке списка');
    }
    return parseProxyList(resp.body);
  } finally {
    if (client == null) c.close();
  }
}

/// Разбирает текст в список прокси: по одному в строке, без пустых и комментариев.
List<String> parseProxyList(String text) {
  return text
      .split(RegExp(r'[\r\n]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !s.startsWith('#'))
      .toList();
}
