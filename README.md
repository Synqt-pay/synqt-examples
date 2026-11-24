# SYNQT examples

Example apps for the SYNQT payment SDKs, one folder per platform: `android/`, `ios/`, `flutter/` and `javascript/` (web). Each is a plain test screen for trying payins against SYNQT's Sandbox or Stable, and its code shows how to call each part of the SDK: the payment sheet, the hosted Payment Web App and following a payin's status.

The examples install the public SDK packages (0.1.0), the way a merchant's app does, with no token or account:

| Platform | Package |
|---|---|
| Android | `com.synqt:synqt-android` on Maven Central |
| iOS | `https://github.com/synqt-pay/synqt-ios` (Swift Package Manager) |
| Flutter | `synqt` on pub.dev |
| Web | `@synqt/js` on npm |

Card payments come from SYNQT's card add-on, which is private and available to PCI DSS compliant merchants on request. Card mode is off by default; each platform below has an "Optional: card mode" section for those with access.

Use dummy payer details only (`test@example.com`, "Test Payer", `0000000000`). Never enter details into real payer apps, and never commit merchant keys or secrets: the token scripts read them from the environment.

## Building from SDK checkouts

For SDK development, each platform has a local switch that builds the SDKs from checkouts next to this repo instead of the published packages, so an SDK change shows up on the next build without releasing it. Clone the repos side by side under these folder names:

```
android/        synqt-pay/synqt-android
android-card/   synqt-pay/synqt-android-card (private, card mode only)
ios/            synqt-pay/synqt-ios
ios-card/       synqt-pay/synqt-ios-card (private, card mode only)
flutter/        synqt-pay/synqt-flutter
flutter-card/   synqt-pay/synqt-flutter-card (private, card mode only)
javascript/     synqt-pay/synqt-js
synqt-examples/ this repo
```

Each platform section says how to turn the switch on.

## Android

`android/` is a plain test screen for trying the SDK against Sandbox or Stable. Its code (`android/src/main/kotlin/com/synqt/demo/MainActivity.kt`) also shows how to call each part of the SDK: `payWithSheet`, `payWithPaymentApp` and `followStatus` are the places to start.

### 1. Set up Android Studio and a device

Install Android Studio with the Android SDK platform 37. Open `android/` (the folder with `settings.gradle.kts`) as a project and let Gradle sync. It installs `com.synqt:synqt-android` from Maven Central, with no token.

To build from the `android` checkout next to this repo instead, add `synqt.local=true` to `android/local.properties` or `~/.gradle/gradle.properties`, or pass `-Psynqt.local=true`. It is then included as a composite build. Create an emulator in Device Manager (a phone, and a Pixel Tablet to see the centred card), or connect a phone with USB debugging on.

### 2. Install the demo

Press Run. From a terminal instead:

```sh
./gradlew installDebug
./gradlew installDebug -Psynqt.local=true   # from the SDK checkout
```

The app installs as `com.synqt.demo`.

#### Optional: card mode

Card mode needs access to SYNQT's private card add-on, for PCI DSS compliant merchants. Add `synqt.card=true` (in `local.properties`, `~/.gradle/gradle.properties` or as `-Psynqt.card=true`). The project then has two build variants, `baseDebug` (the SDK alone) and `cardDebug` (plus the card add-on, which turns CARD on at start), and installs `com.synqt:synqt-android-card` from `https://maven.pkg.github.com/synqt-pay/synqt-android-card`. That needs a GitHub token (classic) with `read:packages` from an account with access: put `gpr.user=<GitHub username>` and `gpr.key=<token>` in `~/.gradle/gradle.properties`, or set `GITHUB_ACTOR` and `GITHUB_TOKEN`. Keep the token out of this repo.

```sh
./gradlew installCardDebug -Psynqt.card=true   # or installBaseDebug
./gradlew installCardDebug -Psynqt.card=true -Psynqt.local=true   # from the android and android-card checkouts, no token
```

Both variants install as `com.synqt.demo`, so one replaces the other.

### 3. Get a token

There are two ways.

**With the merchant's RSA key (preferred).** On your computer, run:

```sh
SYNQT_MERCHANT=<Merchant ID> SYNQT_KEY=path/to/private-key.pem scripts/sandbox-token.sh 100 ZAR
```

It mints a `PAYIN_CREATE` token for a new payin ID and opens the demo with the environment, merchant code, payin ID, token, amount and currency filled in. Add `SYNQT_ENV=stable` for Stable. The private key never goes onto the device.

**With the merchant's secret key**, for merchants without an RSA key yet. In the demo, pick the environment, enter the merchant code and the secret key, and tap GET TOKEN WITH SECRET KEY. It makes a new payin ID, mints a token that also allows the merchant name and the payment operator list, and loads the payment options. The secret key is deprecated by SYNQT and this shortcut is for testing only; it must never ship in a real app.

### 4. Enter the payer's details

Fill in the customer email, first name and last name. The sheet and the Payment Web App receive them as `prefill` or `extra`, so you can see which fields they hide. Use dummy values such as `test@example.com`, never real customer data.

### 5. Pay with the sheet

1. Tap AVAILABLE PAYMENT OPTIONS. The dropdown fills with the methods SYNQT offers this merchant and the sheet supports.
2. Pick a method and tap ENTER DETAILS AND PAY (SDK SHEET).
3. Complete the sheet. On Sandbox the amount decides the outcome: 51 or more succeeds, 3 to 19 fails (see SYNQT's sandbox docs).

The pill at the top shows the payin's status and updates every 5 seconds once a payment is sent. GET STATUS shows the full status in the output area.

### 6. Pay with the Payment Web App

Tap OPEN PAYMENT WEB APP. It opens with the payer's details prefilled and, if you picked one, the dropdown's method preselected; the payer can still choose another. Close it with the X, or finish paying.

### 7. Start again

A payin ID can be used once. For another payment, get a new token (step 3), which also gives a new payin ID.

### Other things to try

- Rotate the device, switch dark mode or change the font size while the sheet is open: the payer's details stay.
- PAYMENT OPERATORS lists every bank and provider SYNQT knows. It needs a token from the secret-key button.
- `adb shell am start -n com.synqt.demo/.MainActivity --es sheet CAPITEC_PAY` opens a sheet without a token, for screenshots. Paying from it fails with HTTP 401.

## iOS

`ios/` is a plain test screen for trying the SDK against Sandbox or Stable, the counterpart of the Android demo. Its code (`ios/SynqtDemo/SynqtDemoApp.swift`) also shows how to call each part of the SDK: `payWithSheet`, `payWithPaymentApp` and `followStatus` are the places to start.

### 1. Open the project

Install Xcode 15 or later (the SDK is tested with Xcode 27.1). Open `ios/SynqtDemo.xcodeproj`. It installs the public package `synqt-ios` (0.1.0) from GitHub, with no account needed.

To build from the `ios` checkout next to this repo instead, open `ios/SynqtDemoLocal.xcworkspace`. Its `Local/` folder links to the checkout under the published package name, so Xcode uses it in place of the released package. Open the `.xcodeproj` again to go back. From a terminal, use `-workspace SynqtDemoLocal.xcworkspace` in place of `-project SynqtDemo.xcodeproj`. Pick the `SynqtDemo` scheme and an iPhone or iPad simulator (an iPad shows the sheet as a centred card), or a device with your own signing team.

### 2. Run the demo

Press Run (Cmd-R). From a terminal in `ios/` instead:

```sh
xcodebuild -project SynqtDemo.xcodeproj -scheme SynqtDemo -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath DerivedData build
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/SynqtDemo.app
xcrun simctl launch booted com.synqt.demo
```

#### Optional: card mode

Card mode needs access to SYNQT's private card add-on, for PCI DSS compliant merchants. Open `ios/SynqtDemoCard.xcodeproj` instead: it shares the same code, which turns CARD on when the add-on is linked, and also installs the private package `synqt-ios-card` from `https://github.com/synqt-pay/synqt-ios-card`. Sign in to a GitHub account with access in Xcode (**Settings > Accounts**), or have SSH or HTTPS git access for `xcodebuild`. To build from the `ios` and `ios-card` checkouts, open `ios/SynqtDemoCardLocal.xcworkspace`. From a terminal, use `-project SynqtDemoCard.xcodeproj` or `-workspace SynqtDemoCardLocal.xcworkspace` in the commands above.

### 3. Get a token

There are two ways.

**With the merchant's RSA key (preferred).** On your Mac, run:

```sh
SYNQT_MERCHANT=<Merchant ID> SYNQT_KEY=path/to/private-key.pem scripts/sandbox-token.sh 100 ZAR
```

It mints a `PAYIN_CREATE` token for a new payin ID and copies the environment, merchant code, payin ID, token, amount and currency. In the demo, tap **Paste from script** (the Simulator shares the Mac's clipboard). Add `SYNQT_ENV=stable` for Stable. The private key never goes onto the device.

**With the merchant's secret key**, for merchants without an RSA key yet. In the demo, pick the environment, enter the merchant code, amount and currency, enter the secret key, and tap **Get token with secret key**. It makes a new payin ID and mints a token that also allows the merchant name and the payment operator list. The secret key is deprecated by SYNQT and this shortcut is for testing only; it must never ship in a real app.

### 4. Enter the payer's details

Fill in the customer email, first name and last name. The sheet receives all three as `prefill`, so you can see which fields it hides. The Payment Web App receives the email, and the two names joined as `accountName`, as it has no first or last name parameters. Use dummy values such as `test@example.com`, never real customer data.

### 5. Pay with the sheet

1. Tap **Available payment options**. The **Method** picker fills with the methods SYNQT offers this merchant and the sheet supports.
2. Pick a method and tap **Enter details and pay (SDK sheet)**.
3. Complete the sheet. On Sandbox the amount decides the outcome: 51 or more succeeds, 3 to 19 fails (see SYNQT's sandbox docs).

The pill in the top left shows the payin's status, checked every 5 seconds from the moment a payment is sent until it is final. **Get status** shows the full status in the output area, which also notes when the sheet comes on screen, when a payment is sent and when it closes.

### 6. Pay with the Payment Web App

Tap **Open Payment Web App**. It opens full screen with the email prefilled and, if you picked one in step 5, that method preselected; the payer can still choose another. Close it with **Close**, or finish paying, and the demo shows the status.

### 7. Start again

A payin ID can be used once. For another payment, get a new token (step 3), which also gives a new payin ID.

### Other things to try

- Rotate the device, switch dark mode or change the text size while the sheet is open: the payer's details stay.
- **Payment operators** lists every bank and provider SYNQT knows. It needs a token from the secret-key button.
- To see the sheet without a token, for screenshots, launch with `SYNQT_DEMO_SHEET` set to a method code. Paying from it fails with SYNQT's 401, shown in the sheet:

  ```sh
  SIMCTL_CHILD_SYNQT_DEMO_SHEET=CAPITEC_PAY xcrun simctl launch booted com.synqt.demo
  ```

## Flutter

`flutter/` is a plain test screen, the counterpart of the native demos. Its `lib/main.dart` also shows how to call each part of the SDK: `_payWithSheet`, `_payWithPaymentApp` and `_followStatus` are the places to start.

1. Generate the platform folders once: `cd flutter && flutter create --platforms=ios,android .` (they are not committed). Add the INTERNET permission to `android/app/src/main/AndroidManifest.xml`.
2. The demo installs `synqt` from pub.dev. To build from the `flutter` checkout next to this repo instead, run `cp pubspec_overrides.local.yaml pubspec_overrides.yaml && flutter pub get` in `flutter/`; delete `pubspec_overrides.yaml` and run `flutter pub get` to go back. It's gitignored.
3. `flutter run` on a simulator, emulator or device.
4. Get a token: on your Mac, run `SYNQT_MERCHANT=<Merchant ID> SYNQT_KEY=path/to/private-key.pem scripts/sandbox-token.sh 100 ZAR` and tap **Paste from script** (the iOS Simulator shares the Mac's clipboard; on Android, paste the JSON by hand). Or, for merchants without an RSA key, enter the merchant code and secret key and tap **Get token with secret key**. The secret key is deprecated by SYNQT and this shortcut is for testing only; it must never ship in a real app.
5. Enter dummy payer details (such as `test@example.com`, never real customer data), tap **Available payment options**, pick a method and tap **Enter details and pay (SDK sheet)**. On Sandbox the amount decides the outcome: 51 or more succeeds, 3 to 19 fails.
6. The pill in the top right shows the payin's status, checked every 5 seconds from the moment a payment is sent. A payin ID can be used once, so get a new token for each payment.

#### Optional: card mode

Card mode needs access to SYNQT's private card add-on (`synqt-pay/synqt-flutter-card`), for PCI DSS compliant merchants. It is a separate entry point, `card/main.dart`, which turns the add-on on and then starts the same demo. It sits outside `lib/` and analysis, so the demo builds without the add-on. In `flutter/`:

```sh
flutter pub add synqt_card --git-url=git@github.com:synqt-pay/synqt-flutter-card.git --git-ref=v0.1.0
flutter run -t card/main.dart
```

This needs git access to the private repo (an SSH key, or a credential helper plus `git config --global url."https://github.com/".insteadOf git@github.com:`). To build from the `flutter` and `flutter-card` checkouts instead, run `cp pubspec_overrides.card.yaml pubspec_overrides.yaml` before the `flutter pub add` above; the override points both packages at the checkouts, so the git repo isn't fetched. Don't commit the `synqt_card` line `flutter pub add` writes into `pubspec.yaml`: run `flutter pub remove synqt_card` (and delete `pubspec_overrides.yaml`) to go back.

The Android demo's token script opens the demo over `adb` with the details filled in. The Flutter script copies them to the clipboard, as the iOS one does. **Paste from script** therefore works on the iOS Simulator only. On the Android emulator, type the details in or use **Get token with secret key**. The Flutter demo has no launch option for showing a sheet without a token, unlike the native demos' `SYNQT_DEMO_SHEET` and `--es sheet`. For screenshots, use the widget tests with `SYNQT_SHOTS` instead.

## Web

`javascript/` is a plain HTML, CSS and JavaScript page (`index.html`, `demo.css`, `demo.js`) for trying the SDK against Sandbox or Stable, the counterpart of the other SDKs' demo apps. `demo.js` also shows how to call each part of the SDK.

1. In `javascript/`, run `npm install`. It installs the SDK, `@synqt/js`, from npm. To use the `javascript` checkout next to this repo instead, run `npm run local`; a plain `npm install` switches back. Then run `scripts/serve-https.sh` in `javascript/` and open the address it prints (`https://localhost:8443/<this repo's folder>/javascript/`). It serves the folder that holds this repo and the SDK checkouts over https on this Mac only, with a self-signed certificate for localhost that it makes once into `javascript/.cert/` (not committed); your browser asks you to trust it the first time. Opening `javascript/index.html` from disk also works, with the limits described below.
2. Get a token: `SYNQT_MERCHANT=<Merchant ID> SYNQT_KEY=path/to/private-key.pem scripts/sandbox-token.sh 100 ZAR` mints a `PAYIN_CREATE` token for a new payin ID and copies the details. Paste them into **Paste from script** and click **Use pasted details**. Add `SYNQT_ENV=stable` for Stable.

   Or, for merchants without an RSA key yet: enter the merchant code, amount and currency, then the **Merchant secret key**, and click **Get token with secret key**. It makes a new payin ID, mints a token that also allows the merchant name and the payment operator list, and loads the payment options. SYNQT has deprecated the secret key, and this is for testing only: the key must never be in a real page. The field is a password field and the page doesn't store it.
3. Click **Available payment options**, pick a method and click **Enter details and pay (SDK sheet)**. On Sandbox the amount decides the outcome: 51 or more succeeds, 3 to 19 fails.
4. Or click **Open Payment Web App**. The payer comes back to the **Return URL (https)** field's address, prefilled with this folder's `return.html` on the https server. Served by `scripts/serve-https.sh`, that is the page's own origin, so the popup closes itself when the payer returns. The SDK and SYNQT accept only https return URLs; you can change the field to your own.

The pill at the top shows the payin's status, checked every 5 seconds from the moment a payment is sent until it is final. A payin ID can be used once, so mint a new token for each payment.

To see the sheet without a token, pick any method under **Preview method** and click **Preview sheet**. Paying from it fails with SYNQT's 401, shown in the sheet.

Opened from disk, the page's origin is `null`, so calls to SYNQT only work if its API accepts that origin, and the sheet shows the system font instead of Instrument Sans. If either gets in the way, use `scripts/serve-https.sh` as in step 1 (the page loads `synqt.js` and its fonts from `node_modules/@synqt/js/`).

The web SDK has no card add-on.

## Licence

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). The SDKs carry their own licences, and the card add-ons are proprietary to SYNQT.

