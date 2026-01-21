import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../utils/system_ui.dart';

class HomeSplashPage extends StatefulWidget {
  const HomeSplashPage({super.key});

  @override
  State<HomeSplashPage> createState() => _HomeSplashPageState();
}

class _HomeSplashPageState extends State<HomeSplashPage>
    with TickerProviderStateMixin {
  late AnimationController _liquidController;
  late AnimationController _logoController;
  late Animation<double> _liquidAnimation;
  late Animation<double> _logoAnimation;

  @override
  void initState() {
    super.initState();

    _liquidController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _liquidAnimation = CurvedAnimation(
      parent: _liquidController,
      curve: const Cubic(0.45, 0.05, 0.55, 0.95),
    );

    _logoAnimation = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    );

    // Start liquid immediately
    _liquidController.forward();

    // Start logo after 400ms
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _logoController.forward();
    });

    // Navigate to home after 1.5 seconds (to allow fade out transition)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/flashcards');
      }
    });
  }

  @override
  void dispose() {
    _liquidController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyleForTop(darkTop: false),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Liquid Layer Background
            AnimatedBuilder(
              animation: _liquidAnimation,
              builder: (context, child) {
                // Sliding up from bottom (-100% to -30%)
                return Positioned(
                  bottom: -size.height * 0.55 +
                      (1.0 - _liquidAnimation.value) * size.height,
                  left: -size.width * 0.35,
                  child: Transform.rotate(
                    angle: _liquidAnimation.value * 0.26, // approx 15 degrees
                    child: Container(
                      width: size.width * 1.25,
                      height: size.height * 2.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00004D),
                        borderRadius: BorderRadius.circular(size.width * 0.6),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Logo Reveal
            Center(
              child: ScaleTransition(
                scale: _logoAnimation,
                child: FadeTransition(
                  opacity: _logoAnimation,
                  child: const Text(
                    'vo',
                    style: TextStyle(
                      fontSize: 150,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                      fontFamily: 'Inter', // Defaulting to Inter as Caveat might not be loaded
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          offset: Offset(0, 4),
                          blurRadius: 10,
                        ),
                      ],
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
