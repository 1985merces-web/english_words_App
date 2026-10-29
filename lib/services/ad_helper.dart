import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'billing_service.dart';
import 'consent_manager.dart';
import 'interstitial_ad_manager.dart';

class AdHelper {
  static final _defaultManager = InterstitialAdManager(load: _loadAd);

  @visibleForTesting
  static InterstitialAdManager? debugManagerOverride;

  static InterstitialAdManager get _manager =>
      debugManagerOverride ?? _defaultManager;

  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/1033173712'; // Safe Google Test ID for debug testing
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-1521649910542801/4624149942'; // Production Ad Unit ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // Test ID
    }
    throw UnsupportedError('Unsupported platform');
  }

  static Future<void> _loadAd({
    required void Function(InterstitialHandle ad) onLoaded,
    required void Function(Object error) onFailed,
  }) =>
      InterstitialAd.load(
        adUnitId: interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => onLoaded(_GoogleInterstitial(ad)),
          onAdFailedToLoad: onFailed,
        ),
      );

  static void loadInterstitialAd() {
    if (BillingService().hasPremiumAccess) return;
    if (debugManagerOverride == null &&
        !ConsentManager.instance.isMobileAdsInitialized) {
      return;
    }
    _manager.preload();
  }

  static void disableAds() {
    _manager.clear();
  }

  static void showInterstitialAd({required VoidCallback onAdClosed}) =>
      _manager.show(onAdClosed: onAdClosed);
}

class _GoogleInterstitial implements InterstitialHandle {
  _GoogleInterstitial(this.ad);

  final InterstitialAd ad;

  @override
  Future<void> show({
    required VoidCallback onShown,
    required VoidCallback onDismissed,
    required void Function(Object error) onFailed,
  }) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onShown(),
      onAdDismissedFullScreenContent: (_) => onDismissed(),
      onAdFailedToShowFullScreenContent: (_, error) => onFailed(error),
    );
    return ad.show();
  }

  @override
  Future<void> dispose() => ad.dispose();
}
