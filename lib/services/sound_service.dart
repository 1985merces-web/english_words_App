import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform audio service for playing local sound cues and chimes.
class SoundService {
  static const MethodChannel _channel =
      MethodChannel('com.mrcsglobal.volary/sound');

  /// Plays the calm, gentle timer completion chime.
  /// On Android, delegates to the native MediaPlayer in MainActivity.
  /// On other platforms or as fallback, plays the system alert chime.
  static Future<void> playTimerChime() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final success = await _channel.invokeMethod<bool>('playTimerChime');
        if (success == true) return;
      } catch (e) {
        debugPrint('[SoundService] Native playTimerChime error: $e');
      }
    }

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }
}
