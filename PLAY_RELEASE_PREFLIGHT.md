# Volary Commercial Release Preflight

Reviewed: 2026-10-27. **Status: Released & Live on Google Play (v1.0.2+6).**
This document records verified preflight checks, commercial launch configuration, and production deployment milestones.

Gemini analysis handoff: [GEMINI_COMMERCIAL_LAUNCH_HANDOFF.md](GEMINI_COMMERCIAL_LAUNCH_HANDOFF.md).

## Product

- Free core card learning with restrained advertising after a one-day trial.
- One-time Premium purchase removes ads and unlocks Reader and Autoplay.
- No subscription or automatic payment after the trial. Regional prices and
  product availability must be configured in Play Console.
- The current trial starts locally when billing is first initialized; it is
  based on device time and is not a server-enforced, account-wide entitlement.

## Critical Release Blockers

1. **Purchase verification:** `lib/services/billing_service.dart` grants and
   caches lifetime access locally on purchase or restore without validating a
   purchase token with a secure backend. It does not reconcile refunds or
   revocations and accepts the legacy local `isPremium` flag. Choose and deploy
   a backend, verify the product, package, purchase state and token using the
   Play Developer API, and handle acknowledgement, retries, restores, and
   revocations. Do not put service-account credentials in the app. Define
   offline entitlement behavior and migration for existing users before
   changing the current cache. [Google billing security guidance](https://developer.android.com/google/play/billing/security)
   and [purchase lifecycle](https://developer.android.com/google/play/billing/integrate).
2. **Ad configuration and privacy:** the Android manifest and
   `lib/services/ad_helper.dart` still contain Google's test AdMob IDs. There is
   no UMP consent flow or privacy-options entry point. The app initializes the
   advertising SDK before collecting consent and may preload ads even during
   Premium. Before enabling production ads, configure the correct AdMob app
   and unit IDs, messages and regional privacy choices, call UMP on launch,
   gate SDK initialization and ad requests appropriately, and test consent,
   withdrawal, failures and applicable regions on devices. [Google UMP Flutter guidance](https://developers.google.com/admob/flutter/privacy).
3. **Privacy and data disclosures:** `web/privacy.html` currently claims no
   third-party sharing, which does not describe the integrated ads, billing,
   and online translation paths. Inventory data and SDK processing, decide the
   audience and supported regions, obtain an appropriate policy review,
   publish an accurate policy at the configured URL, and complete Play Data
   safety and app-content declarations using the actual release behavior.
   [Google Play Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469).
4. **Reader translation:** `lib/screens/reader_screen.dart` sends selected
   words and language codes to `translate.googleapis.com` as a fallback. The
   current endpoint, terms, reliability, provider disclosures, and suitable
   supported production alternative require review; do not represent all
   translation as offline. PDF/DOCX/TXT extraction is local in the app.
5. **Play product and testing:** confirm the Play app and configure the
   non-consumable `volary_premium_lifetime` product, prices and supported
   regions. The old `remove_ads` ID is only a migration path. Test purchase,
   pending payment, cancellation, acknowledgement, refund, restoration,
   offline access, and reinstall through an internal Play track with license
   testers. Do not publish until verification and consent are in place.
6. **Book rights:** the five English classics are recorded in
   `assets/data/reader/SOURCES.md`. Review the selected editions and rights in
   every distribution territory before commercial distribution; US public
   domain status does not settle rights worldwide.
7. **Presentation and device testing:** the current Premium paywall is in
   Ukrainian regardless of interface language. Localize it and its errors for
   supported languages, then test accessibility, small screens, purchases and
   ad consent on real devices, including upgrade and restore scenarios.
8. **English context data:** the app attempts to load
   `assets/data/sets/master_en.jsonl`, which is absent from the current assets.
   Check whether context examples are required and supply properly licensed
   data or remove the dependency before release. Loading currently falls back
   to an empty context map.

## Verified Locally & In Console

- `play` application ID: `com.mrcsglobal.volary`; `site` application ID:
  `com.mrcsglobal.volary.site`. Package version in `pubspec.yaml` updated to
  `1.0.2+6`. Signed release Play App Bundle built at
  `build/app/outputs/bundle/playRelease/app-play-release.aab` (59.6 MB, SHA-256
  `705B7A5E82A8901690F2B9C9F091C4A617309D7AC0017C36552C47C1F96159C1`) containing
  `com.android.vending.BILLING` and Play Billing Library 8.0.0.
- Google Play Console organization account (`MRCS Global`, ID `8926158045735084831`):
  Ireland tax information accepted (`Accepted`, never expires); 15% service fee
  tier enrolled via Account Group `MRCS Global`.
- Google AdMob account created for Ukraine publisher (`pub-1521649910542801`):
  Linked to `Volary: Vocabulary Trainer` (`com.mrcsglobal.volary`). Production
  AdMob App ID: `ca-app-pub-1521649910542801~7951815584`.
- Google Play Console In-App Product `volary_premium_lifetime` created and
  activated (`Active` across 174 countries/regions, base €4.89 / UAH 189.79 / ARS 8400)
  satisfying the `BillingService` purchase flow.
- All 50 tests pass (`flutter test --no-pub`).
- ChaCha20 encryption active across all 14 dataset files in `assets/data/sets/`.

## Release Milestones Completed (2026-10-27)

1. **Store Presence:** Refreshed Short (75/80) & Full descriptions; uploaded 5 curated high-res 1080x2400 phone screenshots.
2. **Review & Publication:** Submitted 19 changes to Google Play Console on Oct 26; approved and published to production on Oct 27, 2026.
3. **AdMob & Verification:** Deployed `app-ads.txt` to `https://volary.mrcs-global.com/app-ads.txt` and `mrcs-global.com`. Production AdMob app linked to Google Play release.
4. **Billing & Products:** Play Billing Library 8.0.0 active via vendored `in_app_purchase_android: 0.5.0`; `volary_premium_lifetime` active across 174 countries under 15% Play Fee Tier.

