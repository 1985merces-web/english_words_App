import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:english_words_app/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WordsApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('What language to learn?'), findsOneWidget);
  });
}
