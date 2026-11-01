# TextSentry for iOS

**Less noise. More signal.** A privacy-first native SwiftUI companion to TextSentry Android (https://github.com/TextSentry/text-sentry-android), starting with **bring your own TypeSafe AI key (BYOK)**. Apple ID sign-in, subscriptions and managed credentials are intentionally deferred.

## What works in this first version

- Native iOS 17+ SwiftUI Home, Review, History and Settings tabs.
- Enter or remove a TypeSafe AI key, stored in iOS Keychain, never App Group storage.
- Manually paste a message, explicitly consent to sending that individual message to TypeSafe's HTTPS System One API, and receive a strict jev-latest yes probability plus a suggested fixed STOP response (preview only).
- Three independently enabled categories: go-vote reminders, political campaigns and marketing ads. All three are enabled by default; selection combines into one OR-based Jev question. Confidence defaults to 95%, configurable 50–100%. None selected = no AI request.
- Safety checks reject security codes, emergency notices, official election administration notices, malformed inputs and excessive message lengths. Provider responses fail closed.
- Encrypted, device-only manual review history (100 most recent). History explicitly states that nothing was sent or deleted.
- In Settings, tap AI connection seven times to enable Developer tools, with additional restrictive prompting and five encrypted local raw request/response traces. Traces omit API keys and auth headers but include message text.
- An included IdentityLookup Message Filter extension can optionally run very conservative offline keyword heuristics on unknown-sender SMS/MMS. It is off by default. It does not use Jev or BYOK, and cannot write history.

## Important iOS platform differences

Apple's IdentityLookup extension receives SMS/MMS from unknown senders only. It cannot inspect iMessage or messages from contacts. For privacy, it cannot use arbitrary network requests or write to storage shared with the app. Server deferral requires an Apple-authorized associated HTTPS service and compatible server contract; direct TypeSafe BYOK requests are not possible from the extension. This first version therefore provides online AI only in the containing app for individually consented manual messages.

**No automatic STOP replies, carrier-inbox deletion, live AI filtering of incoming texts, or incoming message history on iOS.** Offline matches may be placed in Messages' Junk or Promotions categorization once the user enables Apple's filter. Additional instructions and the AI probability threshold affect manual review only, not offline extension decisions.

We do not send SMS contents to TextSentry AWS. Only user-submitted manual review text goes directly to TypeSafe. See PRIVACY.md.

## Build

Requires a Mac, Xcode with an iOS 17+ SDK and XcodeGen (https://github.com/yonaskolb/XcodeGen).

    brew install xcodegen
    xcodegen generate
    open TextSentry.xcodeproj
    xcodebuild test -project TextSentry.xcodeproj -scheme TextSentry -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

Select the TextSentry scheme; it embeds the TextSentryMessageFilter extension. The two targets use bundle IDs org.textsentry.ios and org.textsentry.ios.messagefilter, sharing the App Group group.org.textsentry.shared. **For real-device signing, register both App IDs and the App Group in your Apple Developer account**, select your development team, enable App Groups for both targets, and regenerate provisioning profiles.

To enable offline extension after device installation, visit Settings → Apps → Messages → Unknown & Spam (menu wording varies by iOS version), select TextSentry as the filter, then enable conservative offline filtering in TextSentry Settings. Use real-device tests; SMS delivery and filtering are not realistically exercised in the iOS simulator.

## CI, agents and releases

AGENTS.md describes autonomous branch/PR/test/squash-merge policy. GitHub Actions iOS CI generates the project on macOS, runs XCTest, builds the app and extension, verifies the extension is embedded, and publishes the TextSentry-iOS-simulator-app artifact. No signing credentials are used or required for PRs.

**Simulator build artifacts are not installable on iPhones**. Signed device builds, IPA export and TestFlight require an Apple Developer account, App Group, signing certificates, provisioning profiles and App Store Connect access; none are configured by this repo. CI's unsigned app is a build/test artifact, not an App Store release.

## Roadmap

1. Signed device build and on-device Message Filter evaluation.
2. Review Apple-approved remote filtering options. Do not assume server-side live filtering is compatible with BYOK or the policy against sending message text to TextSentry AWS.
3. Sign in with Apple SSO, subscription controls and managed key retrieval in a separate phase.
