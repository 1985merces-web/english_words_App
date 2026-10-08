import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

class AdHelper {
  static InterstitialAd? _interstitialAd;
  static bool _isAdLoaded = false;

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/1033173712'; // Test ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // Test ID
    }
    throw UnsupportedError('Unsupported platform');
  }

  static void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdLoaded = true;
          debugPrint('InterstitialAd loaded.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd failed to load: $error');
          _isAdLoaded = false;
        },
      ),
    );
  }

  static void showInterstitialAd({required VoidCallback onAdClosed}) {
    if (_isAdLoaded && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _isAdLoaded = false;
          onAdClosed();
          loadInterstitialAd(); // Load the next ad
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('Failed to show InterstitialAd: $error');
          ad.dispose();
          _isAdLoaded = false;
          onAdClosed();
          loadInterstitialAd();
        },
      );
      _interstitialAd!.show();
    } else {
      debugPrint('InterstitialAd not ready yet.');
      onAdClosed();
    }
  }
}
