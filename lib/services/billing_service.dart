import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PremiumAccess { free, trial, lifetime }

enum BillingActionResult {
  started,
  storeUnavailable,
  productUnavailable,
  failed
}

class BillingService extends ChangeNotifier {
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  static const premiumLifetimeProductId = 'volary_premium_lifetime';
  static const _legacyPremiumProductId = 'remove_ads';
  static const _premiumKey = 'premium_lifetime';
  static const _legacyPremiumKey = 'isPremium';
  static const _trialStartedAtKey = 'premium_trial_started_at';
  static const premiumTrialDuration = Duration(days: 1);

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _hasLifetimePremium = false;
  DateTime? _trialStartedAt;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool get hasLifetimePremium => _hasLifetimePremium;
  bool get isTrialActive =>
      !_hasLifetimePremium &&
      _trialStartedAt != null &&
      DateTime.now().isBefore(_trialStartedAt!.add(premiumTrialDuration));
  bool get hasPremiumAccess => _hasLifetimePremium || isTrialActive;
  PremiumAccess get access {
    if (_hasLifetimePremium) return PremiumAccess.lifetime;
    if (isTrialActive) return PremiumAccess.trial;
    return PremiumAccess.free;
  }

  Duration get trialRemaining {
    if (!isTrialActive) return Duration.zero;
    final remaining =
        _trialStartedAt!.add(premiumTrialDuration).difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    _hasLifetimePremium =
        prefs.getBool(_premiumKey) ?? prefs.getBool(_legacyPremiumKey) ?? false;

    final storedTrialStart = prefs.getString(_trialStartedAtKey);
    _trialStartedAt = storedTrialStart == null
        ? DateTime.now()
        : DateTime.tryParse(storedTrialStart) ?? DateTime.now();
    if (storedTrialStart == null) {
      await prefs.setString(
          _trialStartedAtKey, _trialStartedAt!.toIso8601String());
    }

    _subscription = _iap.purchaseStream.listen(
      _listenToPurchaseUpdated,
      onDone: () => _subscription?.cancel(),
      onError: (Object error) => debugPrint('Purchase stream error: $error'),
    );

    _initialized = true;
    notifyListeners();

    unawaited(_restoreSilently());
  }

  Future<ProductDetails?> loadPremiumProduct() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) return null;

      final response =
          await _iap.queryProductDetails({premiumLifetimeProductId});
      if (response.error != null || response.productDetails.isEmpty) {
        return null;
      }
      return response.productDetails.first;
    } catch (error) {
      debugPrint('Premium product query failed: $error');
      return null;
    }
  }

  Future<BillingActionResult> buyPremiumLifetime() async {
    try {
      final product = await loadPremiumProduct();
      if (product == null) {
        final available = await _iap.isAvailable();
        return available
            ? BillingActionResult.productUnavailable
            : BillingActionResult.storeUnavailable;
      }

      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      return BillingActionResult.started;
    } catch (error) {
      debugPrint('Premium purchase start failed: $error');
      return BillingActionResult.failed;
    }
  }

  Future<BillingActionResult> restorePurchases() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) return BillingActionResult.storeUnavailable;
      await _iap.restorePurchases();
      return BillingActionResult.started;
    } catch (error) {
      debugPrint('Restore purchases error: $error');
      return BillingActionResult.failed;
    }
  }

  Future<void> _restoreSilently() async {
    try {
      await _iap.restorePurchases();
    } catch (error) {
      debugPrint('Restore purchases error: $error');
    }
  }

  Future<void> _listenToPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        if (purchaseDetails.productID == premiumLifetimeProductId ||
            purchaseDetails.productID == _legacyPremiumProductId) {
          // Server-side verification will replace this local cache before release.
          await _setLifetimePremium(true);
        }
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        debugPrint('Purchase error: ${purchaseDetails.error}');
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
    }
  }

  Future<void> _setLifetimePremium(bool value) async {
    _hasLifetimePremium = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumKey, value);
    await prefs.remove(_legacyPremiumKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
