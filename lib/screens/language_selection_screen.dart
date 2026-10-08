import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, SystemSound, SystemSoundType, SystemUiOverlayStyle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/language_catalog.dart';
import '../utils/system_ui.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
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
      SystemSound.play(SystemSoundType.alert);
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
    Navigator.of(context).pushReplacementNamed('/flashcards');
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
                      for (final language in LanguageCatalog.available)
                        if (!pickingNative || studyLang != language.code) ...[
                          _LanguageButton(
                            flag: language.flag,
                            label: language.label,
                            subLabel: pickingNative
                                ? language.nativeLabel
                                : 'Study ${language.label}',
                            color: pickingNative ? baseNative : baseStudy,
                            pressedColor:
                                pickingNative ? pressedNative : pressedStudy,
                            isPressed: pressedLang == language.code &&
                                pressedIsNative == pickingNative,
                            onTap: () => _flashAndSelect(
                              language.code,
                              native: pickingNative,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
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
            const Icon(Icons.arrow_forward_ios,
                color: Color(0xFF1A237E), size: 18),
          ],
        ),
      ),
    );
  }
}
