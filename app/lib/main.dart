import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';

import 'ui/add_server_screen.dart';

void main() {
  runApp(const BotswainApp());
}

class BotswainApp extends StatelessWidget {
  const BotswainApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Единое хранилище секретов на всё приложение (Linux → libsecret).
    final secrets = SecureSecretsStore();

    const seed = Colors.indigo;

    return MaterialApp(
      title: 'Botswain',
      // Тема следует за системной: светлая/тёмная выбирается автоматически.
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AddServerScreen(secrets: secrets),
    );
  }
}
