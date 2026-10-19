import 'dart:async';

import 'package:flutter/foundation.dart';

abstract interface class InterstitialHandle {
  Future<void> show({
    required VoidCallback onShown,
    required VoidCallback onDismissed,
    required void Function(Object error) onFailed,
  });

  Future<void> dispose();
}

typedef InterstitialLoader = Future<void> Function({
  required void Function(InterstitialHandle ad) onLoaded,
  required void Function(Object error) onFailed,
});

/// Coordinates one preloaded ad, without retrying continuously on failure.
class InterstitialAdManager {
  InterstitialAdManager({
    required InterstitialLoader load,
    DateTime Function()? now,
    this.minimumInterval = const Duration(minutes: 10),
  })  : _load = load,
        _now = now ?? DateTime.now;

  final InterstitialLoader _load;
  final DateTime Function() _now;
  final Duration minimumInterval;
  InterstitialHandle? _ad;
  bool _loading = false;
  bool _showing = false;
  DateTime? _lastShown;

  void preload() {
    if (_loading || _showing || _ad != null) return;
    _loading = true;
    Future<void>.sync(() => _load(
          onLoaded: (ad) {
            _loading = false;
            _ad = ad;
          },
          onFailed: (error) {
            _loading = false;
            debugPrint('InterstitialAd failed to load: $error');
          },
        )).catchError((Object error) {
      _loading = false;
      debugPrint('InterstitialAd load failed: $error');
    });
  }

  void show({required VoidCallback onAdClosed}) {
    final lastShown = _lastShown;
    if (_showing ||
        (lastShown != null && _now().difference(lastShown) < minimumInterval)) {
      onAdClosed();
      return;
    }

    final ad = _ad;
    if (ad == null) {
      preload();
      onAdClosed();
      return;
    }

    _ad = null;
    _showing = true;
    var finished = false;
    void finish() {
      if (finished) return;
      finished = true;
      _showing = false;
      unawaited(Future<void>.sync(ad.dispose).catchError((Object error) {
        debugPrint('InterstitialAd disposal failed: $error');
      }));
      preload();
      onAdClosed();
    }

    Future<void>.sync(() => ad.show(
          onShown: () {
            if (!finished) _lastShown = _now();
          },
          onDismissed: finish,
          onFailed: (error) {
            debugPrint('InterstitialAd failed to show: $error');
            finish();
          },
        )).catchError((Object error) {
      debugPrint('InterstitialAd show failed: $error');
      finish();
    });
  }
}
