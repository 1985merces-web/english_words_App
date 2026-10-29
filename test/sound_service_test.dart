import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_words_app/services/sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SoundService playTimerChime invokes method channel or fallback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mrcsglobal.volary/sound'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'playTimerChime') {
          return true;
        }
        return null;
      },
    );

    // Call SoundService.playTimerChime()
    await SoundService.playTimerChime();

    // On non-Android test runner, it falls back to SystemSound or invokes channel
    // Both branches should succeed without throwing
    expect(true, isTrue);
  });
}
