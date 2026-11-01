# TextSentry iOS privacy and capability disclosure

Updated November 1, 2026. This describes the initial BYOK iOS app, not planned capabilities.

## Data flow
- Manual Review is a user-initiated action with per-message opt-in. Only after the user explicitly enables consent and taps Analyze, the submitted message and selected category/prompt restrictions are sent directly over HTTPS to api.typesafe.ai/v1/systemone for a Jev decision. A TypeSafe BYOK API key authenticates the request. TypeSafe's own privacy and retention terms apply.
- No SMS text or user API keys are sent to TextSentry's AWS infrastructure. No third-party analytics, tracking SDKs or advertising SDKs are included.
- Optional iOS Message Filter extension performs local pattern checks only, without network access. When Apple's extension is enabled, the system supplies unknown-sender SMS/MMS sender/body to the extension for classification. The extension reads only App Group filter preferences and cannot write message contents to shared app storage.
- iMessage and senders in Contacts are outside the scope of Apple's SMS filter extension.

## On-device storage
- The user's API key stays in iOS Keychain, not Shared UserDefaults and not build artifacts.
- Settings (category selection, offline opt-in, confidence threshold and optional extra instructions) use App Group UserDefaults so the extension can read local settings. Settings are not exported.
- Successful manual reviews are kept in a 100-entry AES-256-GCM encrypted app-private history (raw submitted text, probability, recommended STOP and timestamp). Archive keys stay in Keychain.
- Hidden developer mode can save five AES-GCM encrypted request/response JSON pairs. They contain full submitted messages and selected instructions but exclude API keys and Authorization headers. Disabling developer mode stops future captures; clearing traces erases prior captures.
- The app has Clear History and Delete Local Data controls. Erasing local data removes Keychain credentials, history and traces. Original SMS in Messages is not affected.

## What TextSentry cannot do on iOS
The app cannot automatically reply STOP, delete messages from Apple Messages, read the existing SMS inbox, classify iMessage, or log every filtered incoming SMS. Automatic cloud AI analysis of incoming SMS is not implemented; the extension has neither direct HTTP access nor an authorized TypeSafe BYOK service-deferral path. Offline matches use simple rules, not an AI probability score, and may be imperfect.

## Safe defaults
- Offline extension filtering is off until opted into inside TextSentry and activated in Apple's Settings.
- Each manual provider call requires fresh user consent. No categories = no provider call.
- Authentication and network errors, malformed model responses, codes and official voting information default to no recommendation.
- No claim of App Store approval, device release or Apple ID SSO is made.
