import 'package:flutter/material.dart';
import 'services/billing_service.dart';
import 'screens/home_splash.dart';
import 'screens/flashcards_screen.dart';
import 'screens/language_selection_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BillingService().init();
  runApp(const WordsApp());
}

class WordsApp extends StatefulWidget {
  const WordsApp({super.key});

  @override
  State<WordsApp> createState() => _WordsAppState();
}

class _WordsAppState extends State<WordsApp> {
  bool showENasDefault = true;

  void toggleDefaultView() {
    setState(() {
      showENasDefault = !showENasDefault;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volary - Vocabulary Trainer',
      debugShowCheckedModeBanner: false,
      home: const HomeSplashPage(),
      routes: {
        '/flashcards': (context) => FlashcardScreen(
              showENasDefault: showENasDefault,
              onToggleDefault: toggleDefaultView,
            ),
        '/language-selection': (context) => const LanguageSelectionScreen(),
      },
    );
  }
}
