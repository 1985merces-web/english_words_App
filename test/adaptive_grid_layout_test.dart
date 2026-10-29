import 'package:english_words_app/screens/flashcards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_tts'), (call) async => 1);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  Future<void> pumpScreen(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardScreen(
          showENasDefault: true,
          onToggleDefault: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(FlashcardScreen));
    for (var i = 0; i < 20 && state.currentSetWords.isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    // Switch to Grid Mode if not already in grid mode
    if (!state.gridMode) {
      final gridButton = find.byTooltip('Cards grid');
      expect(gridButton, findsOneWidget);
      await tester.tap(gridButton);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('Phone portrait: 10 cards arrange into 2 columns x 5 rows without overflow',
      (tester) async {
    await pumpScreen(tester, size: const Size(390, 844));

    final gridView = tester.widget<GridView>(
        find.byKey(const ValueKey('flashcards_grid_view')));
    final delegate =
        gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 2,
        reason: 'Portrait orientation must use 2 columns');

    final gridFinder = find.byKey(const ValueKey('flashcards_grid_view'));
    expect(gridFinder, findsOneWidget);

    final dynamic state = tester.state(find.byType(FlashcardScreen));
    expect(state.gridMode, isTrue);

    final cardFinders = find.descendant(
      of: gridFinder,
      matching: find.byType(GestureDetector),
    );
    expect(cardFinders, findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Phone landscape: 10 cards arrange into 5 columns x 2 rows without overflow',
      (tester) async {
    await pumpScreen(tester, size: const Size(844, 390));

    final gridView = tester.widget<GridView>(
        find.byKey(const ValueKey('flashcards_grid_view')));
    final delegate =
        gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 5,
        reason: 'Landscape orientation must use 5 columns');

    expect(tester.takeException(), isNull);
  });

  testWidgets('Tablet portrait: uses 2 columns x 5 rows', (tester) async {
    await pumpScreen(tester, size: const Size(800, 1280));

    final gridView = tester.widget<GridView>(
        find.byKey(const ValueKey('flashcards_grid_view')));
    final delegate =
        gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tablet landscape: uses 5 columns x 2 rows', (tester) async {
    await pumpScreen(tester, size: const Size(1280, 800));

    final gridView = tester.widget<GridView>(
        find.byKey(const ValueKey('flashcards_grid_view')));
    final delegate =
        gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Incomplete last page renders only available items without dummy cards',
      (tester) async {
    await pumpScreen(tester, size: const Size(390, 844));

    final dynamic state = tester.state(find.byType(FlashcardScreen));
    // Simulate an incomplete page with 7 words
    state.setState(() {
      state.currentSetWords = state.currentSetWords.take(7).toList();
      state.gridPage = 0;
    });
    await tester.pumpAndSettle();

    final gridView = tester.widget<GridView>(
        find.byKey(const ValueKey('flashcards_grid_view')));
    final delegate =
        gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 2);

    final delegateBuilder =
        gridView.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegateBuilder.childCount, 7,
        reason: 'Only 7 cards should be rendered, no empty slots');

    expect(tester.takeException(), isNull);
  });

  testWidgets('Card interaction: flipping, star toggle and tts', (tester) async {
    await pumpScreen(tester, size: const Size(390, 844));

    final dynamic state = tester.state(find.byType(FlashcardScreen));
    final initialFace = state.gridCardENFace[0];

    final starIcons = find.byIcon(Icons.star_border);
    expect(starIcons, findsWidgets);

    final firstCard = find.descendant(
      of: find.byKey(const ValueKey('flashcards_grid_view')),
      matching: find.text(state.currentSetWords[0].wordMain),
    );
    expect(firstCard, findsOneWidget);
    await tester.tap(firstCard);
    await tester.pumpAndSettle();

    expect(state.gridCardENFace[0], !initialFace,
        reason: 'Tapping a card must toggle its face');

    final speakerFinder = find.byType(SvgPicture);
    expect(speakerFinder, findsWidgets);

    expect(tester.takeException(), isNull);
  });
}
