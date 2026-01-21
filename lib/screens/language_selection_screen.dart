import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, SystemSound, SystemSoundType, SystemUiOverlayStyle;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/system_ui.dart';
import 'home_splash.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String? studyLang;
  String? nativeLang;
  bool isTransitioning = false;
  String? pressedLang;
  bool pressedIsNative = false;
  bool tapSounds = true;

  @override
  void initState() {
    super.initState();
    tapSounds = true;
  }

  void _playTapClick() {
    // Best-effort: not all devices/platforms will play a click sound.
    if (!tapSounds) return;
    try {
      Feedback.forTap(context);
    } catch (_) {}
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  void _selectStudy(String lang) {
    setState(() {
      isTransitioning = true;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        studyLang = lang;
        isTransitioning = false;
      });
    });
  }

  void _selectNative(String lang) async {
    setState(() => nativeLang = lang);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('study_language', studyLang!);
    await prefs.setString('native_language', lang);
    
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeSplashPage()),
    );
  }

  Future<void> _flashAndSelect(String lang, {required bool native}) async {
    _playTapClick();
    setState(() {
      pressedLang = lang;
      pressedIsNative = native;
    });
    await Future.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    setState(() {
      pressedLang = null;
    });
    if (native) {
      _selectNative(lang);
    } else {
      _selectStudy(lang);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool pickingNative = studyLang != null && !isTransitioning;
    final Color baseStudy = const Color(0xFFEAF2FF);
    final Color baseNative = const Color(0xFFEAF8EE);
    final Color pressedStudy = const Color(0xFFB3E5FC);
    final Color pressedNative = const Color(0xFFB2FFB2);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyleForTop(darkTop: false),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final blur = Tween<double>(begin: 6.0, end: 0.0).animate(animation);
          final fade = Tween<double>(begin: 0.4, end: 1.0).animate(animation);
          return FadeTransition(
            opacity: fade,
            child: AnimatedBuilder(
              animation: blur,
              builder: (context, _) => ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: blur.value,
                  sigmaY: blur.value,
                ),
                child: child,
              ),
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(pickingNative),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    _TitlePill(
                      text: pickingNative
                          ? 'Your native language?'
                          : 'What language to learn?',
                      backgroundColor: pickingNative
                          ? const Color(0xFFB2FFB2) // active green
                          : const Color(0xFFB3E5FC), // active blue
                    ),
                    const SizedBox(height: 48),

                    // ENGLISH (only if not picking native English while study is English)
                    if (!pickingNative || studyLang != 'en')
                      _LanguageButton(
                        flag: '\u{1F1FA}\u{1F1F8}',
                        label: 'English',
                        subLabel: pickingNative ? 'English' : 'Study English',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'en' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'en',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'en')
                      const SizedBox(height: 12),

                    // GERMAN
                    if (!pickingNative || studyLang != 'de')
                      _LanguageButton(
                        flag: '\u{1F1E9}\u{1F1EA}',
                        label: 'German',
                        subLabel: pickingNative ? 'Deutsch' : 'Study German',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'de' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'de',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'de')
                      const SizedBox(height: 12),

                    // FRENCH
                    if (!pickingNative || studyLang != 'fr')
                      _LanguageButton(
                        flag: '\u{1F1EB}\u{1F1F7}',
                        label: 'French',
                        subLabel: pickingNative ? 'Fran\u00E7ais' : 'Study French',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'fr' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'fr',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'fr')
                      const SizedBox(height: 12),

                    // ITALIAN
                    if (!pickingNative || studyLang != 'it')
                      _LanguageButton(
                        flag: '\u{1F1EE}\u{1F1F9}',
                        label: 'Italian',
                        subLabel: pickingNative ? 'Italiano' : 'Study Italian',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'it' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'it',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'it')
                      const SizedBox(height: 12),

                    // SPANISH
                    if (!pickingNative || studyLang != 'es')
                      _LanguageButton(
                        flag: '\u{1F1EA}\u{1F1F8}',
                        label: 'Spanish',
                        subLabel: pickingNative ? 'Espa\u00F1ol' : 'Study Spanish',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'es' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'es',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'es')
                      const SizedBox(height: 12),

                    // PORTUGUESE
                    if (!pickingNative || studyLang != 'pt')
                      _LanguageButton(
                        flag: '\u{1F1F5}\u{1F1F9}',
                        label: 'Portuguese',
                        subLabel: pickingNative ? 'Portugu\u00EAs' : 'Study Portuguese',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'pt' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'pt',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'pt')
                      const SizedBox(height: 12),

                    // TURKISH
                    if (!pickingNative || studyLang != 'tr')
                      _LanguageButton(
                        flag: '\u{1F1F9}\u{1F1F7}',
                        label: 'Turkish',
                        subLabel: pickingNative ? 'T\u00FCrk\u00E7e' : 'Study Turkish',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'tr' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'tr',
                          native: pickingNative,
                        ),
                      ),
                    if (!pickingNative || studyLang != 'tr')
                      const SizedBox(height: 12),

                    // UKRAINIAN
                    if (!pickingNative || studyLang != 'uk')
                      _LanguageButton(
                        flag: '\u{1F1FA}\u{1F1E6}',
                        label: 'Ukrainian',
                        subLabel: pickingNative
                            ? '\u0423\u043A\u0440\u0430\u0457\u043D\u0441\u044C\u043A\u0430'
                            : 'Study Ukrainian',
                        color: pickingNative ? baseNative : baseStudy,
                        pressedColor:
                            pickingNative ? pressedNative : pressedStudy,
                        isPressed:
                            pressedLang == 'uk' && pressedIsNative == pickingNative,
                        onTap: () => _flashAndSelect(
                          'uk',
                          native: pickingNative,
                        ),
                      ),

                    if (pickingNative) ...[
                      const SizedBox(height: 32),
                      TextButton(
                        onPressed: () {
                          _playTapClick();
                          setState(() => studyLang = null);
                        },
                        child: const Text('Back to Study Language'),
                      )
                    ]
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _TitlePill extends StatelessWidget {
  final String text;
  final Color backgroundColor;

  const _TitlePill({
    required this.text,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
            fontFamily: 'Inter',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  final String flag;
  final String label;
  final String subLabel;
  final Color color;
  final Color? pressedColor;
  final bool isPressed;
  final VoidCallback onTap;

  const _LanguageButton({
    required this.flag,
    required this.label,
    required this.subLabel,
    required this.color,
    this.pressedColor,
    this.isPressed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isPressed && pressedColor != null ? pressedColor : color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(
              flag,
              style: const TextStyle(fontSize: 42),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
                Text(
                  subLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF1A237E), size: 18),
          ],
        ),
      ),
    );
  }
}
