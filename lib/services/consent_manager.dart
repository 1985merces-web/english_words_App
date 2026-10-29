import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps Google User Messaging Platform (UMP) consent gathering and gates
/// Google Mobile Ads SDK initialization according to GDPR and Google Play policy.
class ConsentManager {
  static final ConsentManager _instance = ConsentManager._internal();
  factory ConsentManager() => _instance;
  ConsentManager._internal();

  @visibleForTesting
  static ConsentManager? debugInstanceOverride;
  static ConsentManager get instance => debugInstanceOverride ?? _instance;

  bool _isMobileAdsInitialized = false;
  bool get isMobileAdsInitialized => _isMobileAdsInitialized;

  /// Requests updated consent information from UMP. If consent is required,
  /// loads and presents the consent form.
  ///
  /// If [skipIfPremium] is true, no consent is requested and MobileAds is not
  /// initialized because paying users are not shown ads.
  ///
  /// If consent allows ads (`canRequestAds == true`), initializes [MobileAds].
  Future<bool> gatherConsentAndInitializeAds({
    ConsentRequestParameters? params,
    bool skipIfPremium = false,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (skipIfPremium) {
      debugPrint('User has lifetime premium; skipping ad consent and SDK initialization.');
      return false;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST') && params == null) {
      return false;
    }

    final completer = Completer<void>();

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params ?? ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
              if (formError != null) {
                debugPrint('Consent form error: ${formError.errorCode} - ${formError.message}');
              }
            });
          } catch (e) {
            debugPrint('Error showing consent form: $e');
          } finally {
            if (!completer.isCompleted) completer.complete();
          }
        },
        (FormError error) {
          debugPrint('Consent info update failed: ${error.errorCode} - ${error.message}');
          if (!completer.isCompleted) completer.complete();
        },
      );
    } catch (e) {
      debugPrint('Error requesting consent info update: $e');
      if (!completer.isCompleted) completer.complete();
    }

    try {
      await completer.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint('Consent gathering timed out.');
        },
      );
    } catch (_) {}

    final canRequest = await canRequestAds();
    if (canRequest && !_isMobileAdsInitialized) {
      try {
        await MobileAds.instance.initialize();
        _isMobileAdsInitialized = true;
        debugPrint('MobileAds initialized successfully after consent verification.');
      } catch (e) {
        debugPrint('MobileAds initialization failed: $e');
      }
    }

    return canRequest;
  }

  /// Returns true if user consent permits requesting ads.
  Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('Error checking canRequestAds: $e');
      return false;
    }
  }

  /// Checks whether a Privacy Options button/entry point must be offered
  /// in app settings for GDPR / UMP compliance.
  Future<bool> isPrivacyOptionsRequired() async {
    try {
      final status =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (e) {
      debugPrint('Error checking privacy options requirement: $e');
      return false;
    }
  }

  /// Presents the privacy options form so users can review, update, or revoke consent.
  Future<bool> showPrivacyOptionsForm() async {
    final completer = Completer<bool>();
    try {
      await ConsentForm.showPrivacyOptionsForm((formError) {
        if (formError != null) {
          debugPrint(
              'Privacy options form error: ${formError.errorCode} - ${formError.message}');
          completer.complete(false);
        } else {
          completer.complete(true);
        }
      });
    } catch (e) {
      debugPrint('Error showing privacy options form: $e');
      completer.complete(false);
    }
    return completer.future;
  }
}
