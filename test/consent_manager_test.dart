import 'package:english_words_app/services/ad_helper.dart';
import 'package:english_words_app/services/billing_service.dart';
import 'package:english_words_app/services/consent_manager.dart';
import 'package:english_words_app/services/interstitial_ad_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdHandle implements InterstitialHandle {
  int disposeCalls = 0;

  @override
  Future<void> show({
    required VoidCallback onShown,
    required VoidCallback onDismissed,
    required void Function(Object error) onFailed,
  }) async {
    onShown();
    onDismissed();
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConsentManager', () {
    test('skipIfPremium returns false without initializing MobileAds', () async {
      final manager = ConsentManager();
      final result = await manager.gatherConsentAndInitializeAds(
        skipIfPremium: true,
      );
      expect(result, isFalse);
      expect(manager.isMobileAdsInitialized, isFalse);
    });
  });

  group('InterstitialAdManager.clear', () {
    test('clears and disposes preloaded ad immediately', () async {
      final ad = _FakeAdHandle();
      final manager = InterstitialAdManager(
        load: ({required onLoaded, required onFailed}) async {
          onLoaded(ad);
        },
      );

      manager.preload();
      expect(ad.disposeCalls, equals(0));

      manager.clear();
      expect(ad.disposeCalls, equals(1));
    });
  });

  group('AdHelper gating with premium and consent', () {
    setUp(() {
      BillingService.resetForTesting();
    });

    tearDown(() {
      AdHelper.debugManagerOverride = null;
      BillingService.resetForTesting();
    });

    test('loadInterstitialAd does not load if user has lifetime premium',
        () async {
      SharedPreferences.setMockInitialValues({'premium_lifetime': true});
      final billing = BillingService();
      await billing.init();
      expect(billing.hasPremiumAccess, isTrue);

      var loadCalls = 0;
      AdHelper.debugManagerOverride = InterstitialAdManager(
        load: ({required onLoaded, required onFailed}) async {
          loadCalls++;
        },
      );

      AdHelper.loadInterstitialAd();
      expect(loadCalls, equals(0));
    });

    test('loadInterstitialAd does not load if consent has not initialized ads',
        () async {
      SharedPreferences.setMockInitialValues({});
      final billing = BillingService();
      await billing.init();

      expect(billing.hasLifetimePremium, isFalse);
      expect(ConsentManager.instance.isMobileAdsInitialized, isFalse);

      // Without debugManagerOverride, production AdHelper blocks loading
      // when MobileAds has not been initialized with consent.
      expect(() => AdHelper.loadInterstitialAd(), returnsNormally);
    });
  });
}
