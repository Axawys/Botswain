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

    return MaterialApp(
      title: 'Botswain',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: AddServerScreen(secrets: secrets),
    );
  }
}
