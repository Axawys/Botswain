// Дымовой тест UI: экран «добавить сервер» рендерится и содержит поля формы.

import 'package:botswain/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('экран подключения рендерится с полями формы', (tester) async {
    await tester.pumpWidget(const BotswainApp());

    expect(find.text('IP или хост'), findsOneWidget);
    expect(find.text('Логин SSH'), findsOneWidget);
    expect(find.text('Пароль SSH'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Подключиться и поднять агента'),
      findsOneWidget,
    );
  });
}
