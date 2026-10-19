import 'package:english_words_app/services/interstitial_ad_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLoader {
  int calls = 0;
  late void Function(InterstitialHandle) loaded;
  late void Function(Object) failed;

  Future<void> load({
    required void Function(InterstitialHandle ad) onLoaded,
    required void Function(Object error) onFailed,
  }) async {
    calls++;
    loaded = onLoaded;
    failed = onFailed;
  }
}

class FakeAd implements InterstitialHandle {
  int shown = 0;
  int disposed = 0;
  late VoidCallback onShown;
  late VoidCallback onDismissed;
  late void Function(Object) onFailed;

  @override
  Future<void> show({
    required VoidCallback onShown,
    required VoidCallback onDismissed,
    required void Function(Object error) onFailed,
  }) async {
    shown++;
    this.onShown = onShown;
    this.onDismissed = onDismissed;
    this.onFailed = onFailed;
  }

  @override
  Future<void> dispose() async => disposed++;
}

class ThrowingAd implements InterstitialHandle {
  int disposed = 0;

  @override
  Future<void> show({
    required VoidCallback onShown,
    required VoidCallback onDismissed,
    required void Function(Object error) onFailed,
  }) async =>
      throw StateError('platform error');

  @override
  Future<void> dispose() async => disposed++;
}

void main() {
  test('a failed load is retried on a later opportunity, without blocking', () {
    final loader = FakeLoader();
    final manager = InterstitialAdManager(load: loader.load);
    var closed = 0;
    manager.preload();
    manager.preload();
    expect(loader.calls, 1);
    loader.failed('offline');

    manager.show(onAdClosed: () => closed++);
    expect(loader.calls, 2);
    expect(closed, 1);
    manager.show(onAdClosed: () => closed++);
    expect(loader.calls, 2);
    expect(closed, 2);
  });

  test('shown ads respect cooldown and concurrent requests are skipped', () {
    final loader = FakeLoader();
    var time = DateTime.utc(2026, 10, 19);
    final manager = InterstitialAdManager(load: loader.load, now: () => time);
    var closed = 0;
    manager.preload();
    final first = FakeAd();
    loader.loaded(first);
    manager.show(onAdClosed: () => closed++);
    expect(first.shown, 1);
    first.onShown();
    manager.show(onAdClosed: () => closed++);
    expect(closed, 1);
    first.onDismissed();
    first.onDismissed();
    expect(first.disposed, 1);
    expect(closed, 2);
    expect(loader.calls, 2);

    final second = FakeAd();
    loader.loaded(second);
    time = time.add(const Duration(minutes: 9));
    manager.show(onAdClosed: () => closed++);
    expect(second.shown, 0);
    expect(closed, 3);
    time = time.add(const Duration(minutes: 1));
    manager.show(onAdClosed: () => closed++);
    expect(second.shown, 1);
    second.onShown();
    second.onDismissed();
    expect(closed, 4);
  });

  test('failed shows release the ad and load another without a cooldown', () {
    final loader = FakeLoader();
    final manager = InterstitialAdManager(load: loader.load);
    var closed = 0;
    manager.preload();
    final first = FakeAd();
    loader.loaded(first);
    manager.show(onAdClosed: () => closed++);
    first.onFailed('not ready');
    first.onDismissed();
    expect(first.disposed, 1);
    expect(closed, 1);
    expect(loader.calls, 2);

    final second = FakeAd();
    loader.loaded(second);
    manager.show(onAdClosed: () => closed++);
    expect(second.shown, 1);
    second.onDismissed();
    expect(closed, 2);
  });

  test('platform show exceptions close once and permit a new load', () async {
    final loader = FakeLoader();
    final manager = InterstitialAdManager(load: loader.load);
    var closed = 0;
    manager.preload();
    final ad = ThrowingAd();
    loader.loaded(ad);
    manager.show(onAdClosed: () => closed++);
    await Future<void>.delayed(Duration.zero);
    expect(closed, 1);
    expect(ad.disposed, 1);
    expect(loader.calls, 2);
  });
}
