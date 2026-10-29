import 'package:english_words_app/services/billing_service.dart';
import 'package:english_words_app/widgets/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BillingService.resetForTesting();
  });

  tearDown(() {
    BillingService.resetForTesting();
  });

  Widget createPaywallApp({required String featureName, String? languageCode}) {
    return MaterialApp(
      home: Scaffold(
        body: PremiumPaywallSheet(
          featureName: featureName,
          languageCode: languageCode,
        ),
      ),
    );
  }

  group('PremiumPaywallSheet Localization (EN, UK, DE, ES)', () {
    testWidgets('renders English strings when languageCode is en', (tester) async {
      await tester.pumpWidget(createPaywallApp(
        featureName: 'Reader',
        languageCode: 'en',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Volary Premium'), findsOneWidget);
      expect(find.text('Reader is available with Volary Premium.'), findsOneWidget);
      expect(find.text('Ad-free learning'), findsOneWidget);
      expect(find.text('Reader with PDF, DOCX and TXT'), findsOneWidget);
      expect(find.text('Flashcard sets autoplay'), findsOneWidget);
      expect(find.text('One-time payment. No subscription.'), findsOneWidget);
      expect(find.text('Restore purchase'), findsOneWidget);
    });

    testWidgets('renders Ukrainian strings when languageCode is uk', (tester) async {
      await tester.pumpWidget(createPaywallApp(
        featureName: 'Читалка',
        languageCode: 'uk',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Volary Premium'), findsOneWidget);
      expect(find.text('Читалка доступний з Volary Premium.'), findsOneWidget);
      expect(find.text('Навчання без реклами'), findsOneWidget);
      expect(find.text('Читалка з PDF, DOCX і TXT'), findsOneWidget);
      expect(find.text('Автоплей наборів карток'), findsOneWidget);
      expect(find.text('Разова оплата. Без підписки.'), findsOneWidget);
      expect(find.text('Відновити покупку'), findsOneWidget);
    });

    testWidgets('renders German strings when languageCode is de', (tester) async {
      await tester.pumpWidget(createPaywallApp(
        featureName: 'Reader',
        languageCode: 'de',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Volary Premium'), findsOneWidget);
      expect(find.text('Reader ist mit Volary Premium verfügbar.'), findsOneWidget);
      expect(find.text('Lernen ohne Werbung'), findsOneWidget);
      expect(find.text('Reader mit PDF, DOCX und TXT'), findsOneWidget);
      expect(find.text('Autoplay für Kartensets'), findsOneWidget);
      expect(find.text('Einmalige Zahlung. Kein Abo.'), findsOneWidget);
      expect(find.text('Kauf wiederherstellen'), findsOneWidget);
    });

    testWidgets('renders Spanish strings when languageCode is es', (tester) async {
      await tester.pumpWidget(createPaywallApp(
        featureName: 'Lector',
        languageCode: 'es',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Volary Premium'), findsOneWidget);
      expect(find.text('Lector está disponible con Volary Premium.'), findsOneWidget);
      expect(find.text('Aprendizaje sin anuncios'), findsOneWidget);
      expect(find.text('Lector con PDF, DOCX y TXT'), findsOneWidget);
      expect(find.text('Reproducción automática de tarjetas'), findsOneWidget);
      expect(find.text('Pago único. Sin suscripción.'), findsOneWidget);
      expect(find.text('Restaurar compra'), findsOneWidget);
    });

    testWidgets('falls back to English for unlocalized languages', (tester) async {
      await tester.pumpWidget(createPaywallApp(
        featureName: 'Reader',
        languageCode: 'pt',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Volary Premium'), findsOneWidget);
      expect(find.text('Reader is available with Volary Premium.'), findsOneWidget);
      expect(find.text('Ad-free learning'), findsOneWidget);
      expect(find.text('Flashcard sets autoplay'), findsOneWidget);
    });
  });
}
