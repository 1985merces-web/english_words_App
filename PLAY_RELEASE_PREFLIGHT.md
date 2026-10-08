# Google Play Preflight

Checked: 2026-09-23

## Verified

- Package name: `com.mrcsglobal.volary` (`play` flavor).
- Version: `1.0.1` (`versionCode` 4).
- Merged Play release manifest targets Android API 36 and has `minSdkVersion` 24.
- Release signing configuration is present locally; a signed Play app bundle build is in progress.
- App permissions declared by the application manifest are `INTERNET` and Google Play Billing.

## Release blockers

1. The Android manifest and `lib/services/ad_helper.dart` use Google test AdMob identifiers. Production identifiers must be created and installed, or the advertising feature must be removed before publication.
2. `lib/services/billing_service.dart` uses the placeholder product ID `remove_ads`; no Play Console product or production purchase validation has been verified.
3. `web/privacy.html` states that no data is shared with third parties. That is incompatible with a production AdMob integration and must be updated before the Play Data safety declaration is completed.
4. A Google Play Console app record, store listing, content rating, Data safety declaration, App content declarations, and privacy-policy URL still need to be completed by the publisher.
5. The release bundle must be uploaded to an internal test track and installed from Play before a production rollout.

## Product Decision Needed

Choose one before the Play implementation phase:

- **Monetized release:** configure production AdMob and a tested `remove_ads` product, then update privacy/Data safety disclosures.
- **Learning-only first release:** remove or gate advertising and billing before launch, then publish without purchases or ads.

No production configuration or app behavior has been changed by this preflight.
