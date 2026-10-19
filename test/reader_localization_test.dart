import 'package:english_words_app/screens/reader_screen.dart';
import 'package:english_words_app/screens/reader_strings.dart';
import 'package:english_words_app/services/document_text_extractor.dart';
import 'package:file_picker/file_picker.dart';
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

  test('all reader labels and import errors exist in every active language',
      () {
    for (final language in ['en', 'uk', 'de', 'es']) {
      final strings = ReaderStrings(language);
      for (final key in ReaderText.values) {
        expect(strings.text(key), isNotEmpty, reason: '$language: $key');
      }
      for (final error in DocumentTextExtractionError.values) {
        expect(strings.documentError(error), isNotEmpty,
            reason: '$language: $error');
      }
      expect(strings.text(ReaderText.duplicateWord), contains('{word}'));
      expect(strings.text(ReaderText.savedWord), contains('{word}'));
      expect(strings.text(ReaderText.savedWord), contains('{list}'));
    }
    expect(ReaderStrings('unknown').text(ReaderText.title), 'Reader');
  });

  test('document import errors retain their localizable reason', () async {
    final scenarios = [
      (
        file: PlatformFile(name: 'large.txt', size: 11 * 1024 * 1024),
        error: DocumentTextExtractionError.fileTooLarge
      ),
      (
        file: PlatformFile(name: 'file.doc', size: 0),
        error: DocumentTextExtractionError.unsupportedFormat
      ),
      (
        file: PlatformFile(name: 'missing.pdf', size: 0),
        error: DocumentTextExtractionError.pdfAccess
      ),
      (
        file: PlatformFile(name: 'missing.docx', size: 0),
        error: DocumentTextExtractionError.docxRead
      ),
      (
        file: PlatformFile(name: 'missing.txt', size: 0),
        error: DocumentTextExtractionError.txtRead
      ),
    ];
    for (final scenario in scenarios) {
      await expectLater(
        DocumentTextExtractor.extract(scenario.file),
        throwsA(isA<DocumentTextExtractionException>()
            .having((e) => e.error, 'error', scenario.error)),
      );
    }
  });

  testWidgets('Ukrainian native language overrides English app locale',
      (tester) async {
    SharedPreferences.setMockInitialValues({'reader_last_book_id': 55});
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      home: ReaderScreen(
        darkTheme: false,
        studyLang: 'en',
        nativeLang: 'uk',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Читалка'), findsOneWidget);
    expect(find.text('Тексти'), findsOneWidget);
    expect(find.text('Власний текст'), findsOneWidget);
    expect(find.text('Продовжити читання'), findsOneWidget);
    expect(find.text(ReaderStrings('uk').text(ReaderText.tip)), findsOneWidget);
    expect(find.text('Reader'), findsNothing);
    expect(find.text('Continue reading'), findsNothing);

    await tester.tap(find.text('Продовжити читання'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byTooltip('Наступний розділ'), findsOneWidget);
    expect(find.text('Chapter I: The Cyclone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['de', 'es']) {
    testWidgets('custom reader fits a narrow $language screen', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: ReaderScreen(
          darkTheme: true,
          studyLang: 'en',
          nativeLang: language,
        ),
      ));
      await tester.pumpAndSettle();
      await tester
          .tap(find.text(ReaderStrings(language).text(ReaderText.customText)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in [
    (
      native: 'en',
      title: 'Reader',
      tab: 'Your text',
      button: 'Read text',
      empty: 'The text is empty. Enter or paste some text.'
    ),
    (
      native: 'uk',
      title: 'Читалка',
      tab: 'Власний текст',
      button: 'Читати текст',
      empty: 'Текст порожній. Введіть або вставте текст.'
    ),
    (
      native: 'de',
      title: 'Lesen',
      tab: 'Eigener Text',
      button: 'Text lesen',
      empty: 'Der Text ist leer. Gib Text ein oder füge ihn ein.'
    ),
    (
      native: 'es',
      title: 'Lector',
      tab: 'Tu texto',
      button: 'Leer texto',
      empty: 'El texto está vacío. Escribe o pega un texto.'
    ),
  ]) {
    testWidgets('reader uses ${scenario.native} native language',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ReaderScreen(
          darkTheme: false,
          studyLang: 'en',
          nativeLang: scenario.native,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(scenario.title), findsOneWidget);
      await tester.tap(find.text(scenario.tab));
      await tester.pumpAndSettle();
      expect(find.text(scenario.button), findsOneWidget);
      await tester.tap(find.text(scenario.button));
      await tester.pump();
      expect(find.text(scenario.empty), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'like');
      await tester.tap(find.text(scenario.button));
      await tester.pumpAndSettle();
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final readingText = richTexts.firstWhere((text) =>
          text.text is TextSpan &&
          (text.text as TextSpan)
                  .children
                  ?.any((child) => child is TextSpan && child.text == 'like') ==
              true);
      final span = (readingText.text as TextSpan)
          .children!
          .whereType<TextSpan>()
          .firstWhere((child) => child.text == 'like');
      (span.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pumpAndSettle();
      final strings = ReaderStrings(scenario.native);
      expect(find.text(strings.text(ReaderText.translation)), findsOneWidget);
      expect(find.text(strings.text(ReaderText.createList)), findsOneWidget);
      await tester.tap(find.text(strings.text(ReaderText.createList)));
      await tester.pumpAndSettle();
      expect(
          find.text(strings.text(ReaderText.createListTitle)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
