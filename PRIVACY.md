# TextSentry iOS privacy and capability disclosure

Updated November 2, 2026. This describes the current Google sign-in and BYOK iOS beta, not planned capabilities.

## Data flow
- Manual Review is a user-initiated action with per-message consent. For BYOK, submitted message text and user-selected rules go directly to api.typesafe.ai/v1/systemone; the user's TypeSafe retention agreement and billing terms apply. For an eligible Google account with an active subscription, text and rules go directly to OpenRouter's decision endpoint for TypeSafe Jev using a managed key. TextSentry AWS never receives SMS contents.
- Google login uses Apple's ASWebAuthenticationSession to contact Cognito and Google via their hosted sign-in pages. TextSentry AWS auth/config, account status and key endpoints receive Cognito authentication credentials and account metadata, not SMS text. The backend enforces entitlement and managed-key restrictions, including its managed zero-retention policy. No analytics, tracking SDKs or advertising SDKs are included.
- Optional iOS Message Filter extension performs local pattern checks only, without network access. When Apple's extension is enabled, the system supplies unknown-sender SMS/MMS sender/body to the extension for classification. The extension reads only App Group filter preferences and cannot write message contents to shared app storage.
- iMessage and senders in Contacts are outside the scope of Apple's SMS filter extension.

## On-device storage
- BYOK keys and Cognito access/refresh tokens stay in iOS Keychain, not App Group defaults or build artifacts. OpenRouter managed keys are ephemeral RAM-only values, cleared on sign-out and process termination.
- Settings (category selection, offline opt-in, confidence threshold and optional extra instructions) use App Group UserDefaults so the extension can read local settings. Settings are not exported.
- Successful manual reviews are kept in a 100-entry AES-256-GCM encrypted app-private history (raw submitted text, probability, recommended STOP and timestamp). Archive keys stay in Keychain.
- Hidden developer mode can save five AES-GCM encrypted request/response JSON pairs. They contain full submitted messages and selected instructions but exclude API keys and Authorization headers. Disabling developer mode stops future captures; clearing traces erases prior captures.
- The app has Clear History and Delete Local Data controls. Erasing local data signs out, removes Keychain credentials, history and traces, and resets setup. Original SMS in Messages is not affected.

## What TextSentry cannot do on iOS
The app cannot automatically reply STOP, delete messages from Apple Messages, read the existing SMS inbox, classify iMessage, or log every filtered incoming SMS. Automatic cloud AI analysis of incoming SMS is not implemented; the extension has neither direct HTTP access nor an authorized TypeSafe BYOK service-deferral path. Offline matches use simple rules, not an AI probability score, and may be imperfect.

## Safe defaults
- Offline extension filtering is off until opted into inside TextSentry and activated in Apple's Settings.
- Each manual provider call requires fresh user consent. No categories = no provider call.
- Authentication and network errors, malformed model responses, codes and official voting information default to no recommendation.
- Google login does not grant a paid subscription; purchases and Apple Pay are not available in the iOS beta. No claim of App Store approval, device release or Apple ID SSO is made.
