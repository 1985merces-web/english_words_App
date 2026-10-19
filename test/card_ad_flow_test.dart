import 'package:english_words_app/screens/flashcards_screen.dart';
import 'package:english_words_app/services/ad_helper.dart';
import 'package:english_words_app/services/interstitial_ad_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestAd implements InterstitialHandle {
  int showCount = 0;

  @override
  Future<void> show({
    required VoidCallback onShown,
    required VoidCallback onDismissed,
    required void Function(Object error) onFailed,
  }) async {
    showCount++;
    onShown();
    onDismissed();
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('swiping the last single card attempts an interstitial',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_tts'), (call) async => 1);
    final ad = _TestAd();
    AdHelper.debugManagerOverride = InterstitialAdManager(
      load: ({required onLoaded, required onFailed}) async => onLoaded(ad),
    );
    addTearDown(() {
      AdHelper.debugManagerOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    });

    await tester.pumpWidget(MaterialApp(
      home: FlashcardScreen(showENasDefault: true, onToggleDefault: () {}),
    ));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(FlashcardScreen));
    expect(state.currentSetWords, isNotEmpty);
    for (var i = 0; i < 20 && state.enUkDictionary.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 100),
          ));
      await tester.pump();
    }
    expect(state.enUkDictionary, isNotEmpty);
    final translation =
        await state.translateWord(word: 'like', fromLang: 'en', toLang: 'uk');
    expect(translation, 'подобатися');
    state.setState(() => state.currentIndex = state.currentSetWords.length - 1);
    await tester.pumpAndSettle();
    await tester.fling(
        find.byType(AnimatedSwitcher).first, const Offset(-180, 0), 1000);
    await tester.pumpAndSettle();
    expect(state.currentIndex, 0);
    expect(ad.showCount, 1);
    expect(tester.takeException(), isNull);
  });
}
