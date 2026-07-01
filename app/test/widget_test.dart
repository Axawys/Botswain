// Дымовой тест UI: главный экран рендерится с двумя вкладками.

import 'package:botswain/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('главный экран показывает вкладки Локально и SSH',
      (tester) async {
    await tester.pumpWidget(const BotswainApp());

    expect(find.text('Локально'), findsOneWidget);
    expect(find.text('SSH'), findsOneWidget);
    // Локальная вкладка активна по умолчанию.
    expect(
      find.widgetWithText(FilledButton, 'Активировать агента локально'),
      findsOneWidget,
    );
  });
}
