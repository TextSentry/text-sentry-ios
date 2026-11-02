# TextSentry iOS autonomous engineering contract

## Product constraints
- Mirror Android's TypeSafe Jev BYOK and managed OpenRouter decision-model flow, categories, minimum yes probability (50–100%, default 90%), safeguards, developer prompt restrictions, local history and privacy language when Apple APIs support it.
- iOS IdentityLookup filters only unknown-sender SMS/MMS, not iMessage or Contacts. Its extension cannot make direct network calls or write App Group files.
- Current iOS functionality: Google/Cognito OAuth PKCE, existing-subscription managed-key manual reviews, explicitly consented manual BYOK Jev reviews, opt-in offline conservative extension rules. Do not claim Jev runs on incoming SMS, automatic STOP is sent, SMS is deleted, or incoming SMS history exists.
- Do not route users' SMS through TextSentry AWS. No analytics, no telemetry, no user SMS content in CI or logs.
- BYOK: https://api.typesafe.ai/v1/systemone, model jev-latest. Managed: https://openrouter.ai/api/alpha/decisions, model typesafe/jev-1.14 with a RAM-only backend-issued key. Both use one noul questions.reply with categories ORed; fail closed on invalid JSON, HTTP failures, OTPs, official election notices and ambiguous content.
- Never put BYOK keys in UserDefaults or App Group storage. Store API keys and local archive keys in iOS Keychain; AES-GCM encrypt message/traces on disk.
- Extension reads ONLY preferences from App Group and never reads a key, archives message contents, or makes HTTP requests. Offline rules are disabled by default and never portrayed as AI.
- Google sign-in uses only the backend-provided Cognito public client and registered redirect. Never bundle a client secret. Persist OAuth tokens in Keychain, managed API keys in RAM only. Sign-out must clear all auth state; no user-supplied identity can bypass backend subscription validation. Do not implement Sign in with Apple or iOS purchases until separately requested. Never build unsupported automatic replies or message deletion.

## Autonomous development workflow
1. Read this file, README, PRIVACY, project.yml, test suite, open PRs and current GitHub Actions status.
2. Branch from current main; never commit feature code directly to main.
3. Add a failing test for changed behavior, implement minimally, then run XcodeGen, xcodebuild test and simulator build.
4. Open a focused PR, inspect its diff and CI runs. Fix failures and rerun until the build and tests pass.
5. Squash-merge after required GitHub checks are green and no branch rules block it; verify main CI and artifacts. Do not ask for routine approvals.
6. Ask for human access only for Apple Developer signing/provisioning, App Group registration, repo administration, hardware-only extension testing or consequential product changes.

## CI and release
- macOS workflow runs on pull_request, main pushes and workflow_dispatch. It generates the Xcode project from project.yml, runs simulator unit tests, builds the app + extension and uploads an unsigned simulator .app ZIP.
- Simulator artifacts cannot be installed on a physical iPhone. Signed device builds and TestFlight require Apple Developer identifiers, App Groups, certificates, provisioning and App Store Connect configuration; don't claim those are configured.
- Never expose signing credentials to ordinary PR jobs. Keep a separate optional trusted main release job once signing is provisioned.
- Review framework/entitlement changes carefully. New Apple service integration requires review of user-data transmission and an updated PRIVACY.md.
- External BYOK network analysis only runs after explicit per-review consent in the containing app; traces are encrypted and contain full request/response JSON but never Authorization headers.
