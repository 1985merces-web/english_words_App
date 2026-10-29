import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/billing_service.dart';
import '../services/consent_manager.dart';
import '../utils/system_ui.dart';

class HomeSplashPage extends StatefulWidget {
  const HomeSplashPage({super.key});

  @override
  State<HomeSplashPage> createState() => _HomeSplashPageState();
}

class _HomeSplashPageState extends State<HomeSplashPage>
    with TickerProviderStateMixin {
  late final AnimationController _surfaceController;
  late final AnimationController _logoController;
  late final Animation<double> _surfaceAnimation;
  late final Animation<double> _logoAnimation;

  @override
  void initState() {
    super.initState();
    _surfaceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _surfaceAnimation = CurvedAnimation(
      parent: _surfaceController,
      curve: Curves.easeOutCubic,
    );
    _logoAnimation = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutBack,
    );

    _surfaceController.forward();
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _logoController.forward();
    });
    _continueToApp();
  }

  Future<void> _continueToApp() async {
    final consentFuture = ConsentManager.instance.gatherConsentAndInitializeAds(
      skipIfPremium: BillingService().hasLifetimePremium,
    );
    final delayFuture =
        Future<void>.delayed(const Duration(milliseconds: 1800));
    final prefsFuture = SharedPreferences.getInstance();

    await Future.wait([consentFuture, delayFuture]);
    final prefs = await prefsFuture;
    final hasLanguage = prefs.getString('study_language') != null &&
        prefs.getString('native_language') != null;

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      hasLanguage ? '/flashcards' : '/language-selection',
    );
  }

  @override
  void dispose() {
    _surfaceController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyleForTop(darkTop: true),
      child: Scaffold(
        backgroundColor: const Color(0xFF071A2E),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -size.height * 0.16,
              right: -size.width * 0.35,
              child: Transform.rotate(
                angle: -0.24,
                child: Container(
                  width: size.width * 1.2,
                  height: size.height * 0.42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2AB7A9).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(size.width),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -size.height * 0.18,
              left: -size.width * 0.42,
              child: Transform.rotate(
                angle: 0.3,
                child: Container(
                  width: size.width * 1.28,
                  height: size.height * 0.36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F80ED).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(size.width),
                  ),
                ),
              ),
            ),
            Center(
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.82, end: 1).animate(
                  _surfaceAnimation,
                ),
                child: FadeTransition(
                  opacity: _surfaceAnimation,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: Container(
                          width: 184,
                          height: 184,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.58),
                              width: 1.2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: ScaleTransition(
                            scale: _logoAnimation,
                            child: FadeTransition(
                              opacity: _logoAnimation,
                              child: const Text(
                                'VO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 82,
                                  fontStyle: FontStyle.italic,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black38,
                                      offset: Offset(0, 5),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
