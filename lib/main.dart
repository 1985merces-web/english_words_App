import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_splash.dart';
import 'screens/flashcards_screen.dart';
import 'screens/language_selection_screen.dart';

void main() {
  runApp(const WordsApp());
}

class WordsApp extends StatefulWidget {
  const WordsApp({super.key});

  @override
  State<WordsApp> createState() => _WordsAppState();
}

class _WordsAppState extends State<WordsApp> {
  bool? hasLanguage;
  bool showENasDefault = true;

  @override
  void initState() {
    super.initState();
    _checkLanguage();
  }

  Future<void> _checkLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final native = prefs.getString('native_language');
    final study = prefs.getString('study_language');
    setState(() {
      hasLanguage = (native != null && study != null);
    });
  }

  void toggleDefaultView() {
    setState(() {
      showENasDefault = !showENasDefault;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show empty container while checking prefs
    if (hasLanguage == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
        debugShowCheckedModeBanner: false,
      );
    }

    return MaterialApp(
      title: 'Volary - Vocabulary Trainer',
      debugShowCheckedModeBanner: false,
      // If language is set -> HomeSplashPage (which goes to Flashcards)
      // If not set -> LanguageSelectionScreen
      home: hasLanguage! ? const HomeSplashPage() : const LanguageSelectionScreen(),
      routes: {
        '/flashcards': (context) => FlashcardScreen(
              showENasDefault: showENasDefault,
              onToggleDefault: toggleDefaultView,
            ),
      },
      // Remove initialRoute as 'home' handles it
    );
  }
}
