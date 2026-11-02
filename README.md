# TextSentry for iOS

**Less noise. More signal.** Native iOS 17+ companion to [TextSentry Android](https://github.com/TextSentry/text-sentry-android), using the same Jev decision model and privacy principles where iOS permits.

## Implemented

- Google sign-in via the **existing TextSentry Cognito public client**, OAuth authorization-code + S256 PKCE and an ephemeral Apple authentication session. Session tokens are stored in the iOS Keychain; signing out removes them. The Google account chooser is requested on each fresh sign-in.
- An existing **active live TextSentry subscription** can use the existing Cognito-protected `GET /v1/key` API. Keys are capped at $1/month by the backend, restricted there to the supported decision model, and **held in process memory only** on iOS. The app uses `https://openrouter.ai/api/alpha/decisions`, model `typesafe/jev-1.14`, for managed analyses. The backend, not the app, enforces entitlement. Sandbox purchase status is not represented as live access.
- BYOK alternative: user explicitly accepts TypeSafe data-retention and billing responsibility, then supplies a TypeSafe key held in Keychain. Manual analysis uses `https://api.typesafe.ai/v1/systemone` with `jev-latest`. Never send a BYOK key to OpenRouter. Settings hide BYOK controls while signed in.
- Mandatory welcome/account screen and concise iPhone-specific setup before the main tab view. Home, Review, encrypted local manual History and Settings.
- Three categories (nonpartisan vote reminders, political campaigns, marketing), OR-composed in one Jev question. **Default confidence 90%**, adjustable from 50% to 100%. No categories means no request.
- Per-message manual consent, strict safe-message exclusions, fixed **STOP preview only**, no generated text, no replies sent. Provider errors fail closed.
- Local AES-256-GCM encrypted history (100 records), hidden developer mode with encrypted request/response diagnostics (five records), and local data erase.
- Optional conservative **offline** IdentityLookup Message Filter extension for unknown-sender SMS/MMS. Disabled until user opts in; additional activation in iPhone Settings is required. It never sees credentials or sends network requests.

## iOS differs from Android

Apple's message-filter extension cannot read the existing Messages inbox, contact-sender messages or iMessage, and cannot automatically reply STOP or delete SMS. The extension currently performs **offline pattern matching only**, not live Jev inference. No cloud filtering, incoming-message history or automatic STOP is claimed. Manual Jev review is performed by the containing app only, with explicit per-message consent. SMS contents never go to TextSentry AWS.

**Apple Pay, Apple in-app purchases and new iOS subscription checkout are not implemented.** Google sign-in works without purchase but managed AI keys require an existing active eligible subscription; users without one will see a subscription-required error. Do not advertise subscriptions as purchasable within this iOS build.

## Build, test and device setup

Requires a Mac, Xcode with iOS 17+ SDK and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
xcodebuild test -project TextSentry.xcodeproj -scheme TextSentry -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

The app and extension use bundle IDs `org.textsentry.ios` and `org.textsentry.ios.messagefilter`, with App Group `group.org.textsentry.shared`. Real-device signing requires the Apple Developer team to register the IDs, the App Group and profiles. OAuth redirects use `textsentry://auth/callback`, already supported by the Android Cognito auth configuration; the iOS app also declares this URL scheme. The Cognito discovery endpoint must keep this redirect and allow authorization-code PKCE without a client secret.

Enable local SMS filtering on a real device via Settings → Apps → Messages → Unknown & Spam and choose TextSentry, then opt into offline filtering in the app. The iOS simulator does not reproduce real incoming-message filtering.

## CI and releases

The `.github/workflows/ios.yml` GitHub Actions workflow generates Xcode projects on macOS, runs XCTest, builds the iOS app + extension, verifies the extension bundle and publishes **an unsigned simulator artifact only**. A signed device build, IPA or TestFlight deployment requires Apple Developer certificates, provisioning and App Store Connect setup; it is not yet automated. No signing secrets should be added to ordinary PR jobs.

See [PRIVACY.md](PRIVACY.md) and [AGENTS.md](AGENTS.md). Next planned work: physical-device smoke tests, Apple purchase integration and App Store distribution review.
