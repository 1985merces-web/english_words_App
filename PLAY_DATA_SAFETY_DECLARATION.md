# Google Play Data Safety Questionnaire Guide: Volary

This document provides exact answers for the **Data Safety** section in Google Play Console for **Volary** (`com.mrcsglobal.volary`).

---

## 1. Overview Questions

| Question | Answer | Rationale |
| :--- | :--- | :--- |
| **Does your app collect or share any of the required user data types?** | **Yes** | Google AdMob and Google Play Billing process device identifiers and purchase tokens. |
| **Is all of the user data collected by your app encrypted in transit?** | **Yes** | All network traffic (AdMob, Play Billing, HTTPS word translation) uses TLS/HTTPS. |
| **Do you provide a way for users to request that their data be deleted?** | **Yes** | Users can wipe app data via Android Settings or delete custom lists locally. |

---

## 2. Data Types Declaration

### A. Location
- **Data type:** Approximate location (Coarse location)
  - **Collected:** Yes
  - **Shared:** Yes (with Google AdMob SDK)
  - **Processed ephemerally:** Yes
  - **Is this data required or optional?** Required for free ad-supported tier (unless upgraded to Premium).
  - **Purposes:**
    - `Advertising or marketing` (serving geographically relevant advertisements).
    - `Fraud prevention, security, and compliance` (determining regional GDPR compliance).

### B. Financial Info
- **Data type:** Purchase history
  - **Collected:** Yes
  - **Shared:** No (handled directly by Google Play In-App Billing)
  - **Processed ephemerally:** No (linked to Google Play account)
  - **Is this data required or optional?** Optional (only if user purchases Volary Premium).
  - **Purposes:**
    - `App functionality` (unlocking lifetime access and restoring purchases across devices).
    - `Fraud prevention, security, and compliance`.

### C. Device or Other Identifiers
- **Data type:** Device or other identifiers (Advertising ID / AAID)
  - **Collected:** Yes
  - **Shared:** Yes (with Google AdMob)
  - **Processed ephemerally:** No
  - **Is this data required or optional?** Required for free ad-supported tier; can be reset/opted out via Android OS Settings or UMP consent form. Excluded entirely for Premium users.
  - **Purposes:**
    - `Advertising or marketing` (frequency capping, ad attribution, and personalized ads if consented).
    - `Analytics` (ad delivery performance).
    - `Fraud prevention, security, and compliance`.

### D. App Info and Performance
- **Data type:** Crash logs / Diagnostics
  - **Collected:** Yes (via Google Play Services / AdMob)
  - **Shared:** No
  - **Processed ephemerally:** Yes
  - **Purposes:**
    - `Analytics`
    - `App functionality`

---

## 3. Data Not Collected (Mark "No")
- **Personal info:** Name, Email, Address, Phone number (NO).
- **Photos and videos:** NO.
- **Audio files:** NO (Text-to-speech runs on-device).
- **Health and fitness:** NO.
- **Messages:** NO.
- **Contacts:** NO.
- **Web browsing history:** NO.

---

## 4. Privacy Policy URL
- Set to: `https://volary.mrcs-global.com/privacy`
