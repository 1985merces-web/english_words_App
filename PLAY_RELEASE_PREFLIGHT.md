# Volary Commercial Release Preflight

Reviewed: 2026-10-19. **Status: not ready for a commercial release.** This
document describes the current workspace, not the state of any console, website,
server, or production release. No Play or AdMob settings were changed.

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

## Verified Locally

- `play` application ID: `com.mrcsglobal.volary`; `site` application ID:
  `com.mrcsglobal.volary.site`. The current package version in `pubspec.yaml` is
  `1.0.1+4`. No new Play bundle was built or uploaded in this task.
- Both single-card gesture paths now share the same end-of-set handling; grid
  sets, including short sets, use the same completion calculation. Premium
  access still suppresses the display attempt.
- Failed test-ad loads are retried at a later opportunity; ad requests are not
  retried continuously. A 10-minute in-process cooldown applies after a shown
  ad; it does not persist across process restarts.
- English-to-Ukrainian custom-list lookup now uses the existing aligned CSV
  assets and waits for dictionary loading. The source CSV files were not changed.
- `flutter test --no-pub` passed 30 tests, including isolated ad and navigation
  tests. `flutter analyze --no-pub` reports one existing `WillPopScope` info
  notice. SDK integration, real ad delivery, Play billing, regional consent,
  backend verification and physical-device behavior remain unverified.

## Decisions and Inputs Needed

- Play Console and AdMob account/app availability, intended launch countries,
  age audience and proposed regional price points.
- A secure backend/hosting choice for purchase verification, including
  operational ownership and privacy implications.
- Approval of the production privacy policy, terms, and online translation
  provider after review. Keep credentials out of chat and out of the repository.
- A separate explicit release authorization before changing production Play
  configuration, building a release artifact for distribution, or publishing.
