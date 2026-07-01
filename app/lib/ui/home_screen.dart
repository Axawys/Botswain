import 'package:botswain_core/botswain_core.dart';
import 'package:flutter/material.dart';

import 'local_tab.dart';
import 'ssh_tab.dart';

/// Главный экран с двумя вкладками: «Локально» (агент на своём ПК) и «SSH»
/// (агент на VPS). Режимы независимы и не мешают друг другу.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.secrets});

  final SecretsStore secrets;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Botswain'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.computer), text: 'Локально'),
              Tab(icon: Icon(Icons.dns), text: 'SSH'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const LocalTab(),
            SshTab(secrets: secrets),
          ],
        ),
      ),
    );
  }
}
