import 'dart:convert';

import 'package:english_words_app/models/reader_book.dart';
import 'package:english_words_app/screens/reader_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  test('all bundled books contain the expected complete chapter sequences',
      () async {
    const counts = {11: 12, 55: 24, 113: 27, 1661: 12, 215: 7};
    const firstTitles = {
      11: 'CHAPTER I: Down the Rabbit-Hole',
      55: 'Chapter I: The Cyclone',
      113: 'CHAPTER I: THERE IS NO ONE LEFT',
      1661: 'I. A SCANDAL IN BOHEMIA',
      215: 'Chapter I. Into the Primitive',
    };
    const lastTitles = {
      11: 'CHAPTER XII: Alice’s Evidence',
      55: 'Chapter XXIV: Home Again',
      113: 'CHAPTER XXVII: IN THE GARDEN',
      1661: 'XII. THE ADVENTURE OF THE COPPER BEECHES',
      215: 'Chapter VII. The Sounding of the Call',
    };
    expect(ReaderBookInfo.englishBooks, hasLength(5));
    for (final info in ReaderBookInfo.englishBooks) {
      final book = await ReaderBook.load(info);
      expect(book.chapters, hasLength(counts[info.id]!));
      expect(book.chapters.first.title, firstTitles[info.id]);
      expect(book.chapters.last.title, lastTitles[info.id]);
      for (final chapter in book.chapters) {
        expect(chapter.paragraphs, isNotEmpty);
        expect(chapter.paragraphs.every((p) => p.trim().isNotEmpty), isTrue);
        expect(
            chapter.paragraphs.join(' '), isNot(contains('PROJECT GUTENBERG')));
      }
    }
  });

  testWidgets('English reader opens books and navigates chapters',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: ReaderScreen(darkTheme: false, studyLang: 'en', nativeLang: 'en'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester
        .tap(find.text('The Wonderful Wizard of Oz — L. Frank Baum').last);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Chapter I: The Cyclone'), findsOneWidget);
    final paragraph =
        tester.widgetList<RichText>(find.byType(RichText)).firstWhere(
              (richText) =>
                  richText.text is TextSpan &&
                  (richText.text as TextSpan).children?.any(
                            (child) =>
                                child is TextSpan && child.text == 'farmer',
                          ) ==
                      true,
            );
    final word = (paragraph.text as TextSpan)
        .children!
        .whereType<TextSpan>()
        .firstWhere((span) => span.text == 'farmer');
    (word.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Translation:'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Next chapter'), findsOneWidget);
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter II: The Council with the Munchkins'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Previous chapter'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter I: The Cyclone'), findsOneWidget);
    await tester.drag(
        find.byType(CustomScrollView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress survives reader reopening and is separate per book',
      (tester) async {
    const reader = MaterialApp(
      home: ReaderScreen(darkTheme: false, studyLang: 'en', nativeLang: 'en'),
    );
    Future<void> choose(String title) async {
      await tester.tap(find.byType(DropdownButton<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(title).last);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(reader);
    await tester.pumpAndSettle();
    await choose('The Wonderful Wizard of Oz — L. Frank Baum');
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(CustomScrollView).last, const Offset(0, -850));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final prefs = await SharedPreferences.getInstance();
    final oz = jsonDecode(prefs.getString('reader_book_progress_55')!) as Map;
    expect(oz['chapter'], 1);
    expect(oz['paragraph'], greaterThan(0));

    await choose("Alice's Adventures in Wonderland — Lewis Carroll");
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expect(jsonDecode(prefs.getString('reader_book_progress_55')!), oz);
    expect(prefs.getInt('reader_last_book_id'), 11);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    await tester.pumpWidget(reader);
    await tester.pumpAndSettle();
    expect(find.text('Continue reading'), findsOneWidget);
    await tester.tap(find.text('Continue reading'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('CHAPTER II: The Pool of Tears'), findsOneWidget);

    await choose('The Wonderful Wizard of Oz — L. Frank Baum');
    expect(find.text('Chapter II: The Council with the Munchkins'),
        findsOneWidget);
    expect(find.byKey(ValueKey('book-3-chapter-1-start-${oz['paragraph']}')),
        findsOneWidget);
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, 650));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final earlier =
        jsonDecode(prefs.getString('reader_book_progress_55')!) as Map;
    expect(earlier['paragraph'], lessThan(oz['paragraph']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling is saved when the reader closes immediately',
      (tester) async {
    const reader = MaterialApp(
      home: ReaderScreen(darkTheme: false, studyLang: 'en', nativeLang: 'en'),
    );
    await tester.pumpWidget(reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester
        .tap(find.text('The Wonderful Wizard of Oz — L. Frank Baum').last);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(CustomScrollView).last, const Offset(0, -850));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    final prefs = await SharedPreferences.getInstance();
    final progress =
        jsonDecode(prefs.getString('reader_book_progress_55')!) as Map;
    expect(progress['paragraph'], greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid saved progress is clamped to a valid chapter',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'reader_last_book_id': 55,
      'reader_book_progress_55': '{"chapter":9999,"paragraph":9999}',
    });
    await tester.pumpWidget(const MaterialApp(
      home: ReaderScreen(darkTheme: false, studyLang: 'en', nativeLang: 'uk'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продовжити читання'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Chapter XXIV: Home Again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English books are not offered for another study language',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ReaderScreen(darkTheme: false, studyLang: 'de', nativeLang: 'uk'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    expect(
        find.text('The Wonderful Wizard of Oz — L. Frank Baum'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
