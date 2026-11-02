import SwiftUI

private struct SentrySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct HomeView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var account: GoogleAccountStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 46))
                        .foregroundStyle(.indigo)
                    Text("Less noise. More signal.")
                        .font(.title2.bold())
                    Text("Privacy-first message review with TypeSafe Jev.")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                SentrySection(title: "AI connection") {
                    Label(account.signedIn ? "Google account connected" :
                          account.hasBYOK ? "TypeSafe key saved on device" : "Connect an account",
                          systemImage: account.signedIn ? "person.crop.circle.badge.checkmark" : "key")
                    Text("Jev · Confidence: \(Int(settings.value.threshold * 100))%")
                        .foregroundStyle(.secondary)
                }

                SentrySection(title: "iPhone filtering") {
                    Text(settings.value.offlineFilteringEnabled
                         ? "Local rules enabled. Enable TextSentry in iPhone Messages settings."
                         : "Local filtering is off until you opt in.")
                    Text("Go to Settings → Apps → Messages → Unknown & Spam, then select TextSentry if available. Only unknown-sender SMS/MMS can be filtered.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("iOS does not allow this extension to call Jev directly, send STOP, delete messages or collect an inbox history.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                SentrySection(title: "Privacy first") {
                    Text("Only messages you submit for manual review go directly to the selected AI provider. No message text goes to TextSentry servers.")
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("TextSentry")
    }
}

struct ManualReviewView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var traces: TraceStore
    @EnvironmentObject private var account: GoogleAccountStore
    @State private var message = ""
    @State private var consent = false
    @State private var evaluating = false
    @State private var result: JevEvaluation?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Paste or type a message to assess whether it matches your chosen categories. This is a manual recommendation; iOS never sends STOP.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $message)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Message to review")
                    .onChange(of: message) { _, _ in result = nil }
                Text("\(message.count) / 1600 characters")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Message") }

            Section("Consent") {
                Toggle(account.signedIn ? "Send this message directly to OpenRouter for Jev analysis" : "Send this message directly to TypeSafe for analysis", isOn: $consent)
                Text("Only the message and selected filtering instructions are sent directly to the AI provider. The message is never sent to TextSentry AWS.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await analyze() }
                } label: {
                    if evaluating { ProgressView() }
                    else { Label("Analyze with Jev", systemImage: "sparkles") }
                }
                .disabled(evaluating || !consent || message.isEmpty || message.count > 1600 ||
                          settings.value.categoryMask == 0 || (!account.signedIn && !account.hasBYOK))
            }

            if let result {
                Section("Recommendation") {
                    Label(result.matches ? "Matches your filters — suggested STOP" : "No STOP suggested",
                          systemImage: result.matches ? "exclamationmark.shield" : "checkmark.shield")
                    Text("Jev yes probability: \(result.probability.formatted(.percent.precision(.fractionLength(1))))")
                    Text("This is a preview. No reply was sent and no SMS was deleted.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Review message")
    }

    @MainActor
    private func analyze() async {
        guard consent else { return }
        result = nil
        errorMessage = nil
        evaluating = true
        let reviewedMessage = message
        let capturedSettings = settings.value
        let managed = account.signedIn
        defer { evaluating = false; consent = false }
        do {
            let key: String
            if managed { key = try await account.managedKey() }
            else if let ownKey = KeychainVault.apiKey { key = ownKey }
            else { throw JevError.invalidSettings }
            let evaluation = try await JevClient().analyze(
                message: reviewedMessage, key: key, settings: capturedSettings,
                provider: managed ? .managed : .byok,
                trace: { request, response in
                    Task { @MainActor in
                        if settings.value.developerModeEnabled {
                            traces.capture(request: request, response: response)
                        }
                    }
                }
            )
            result = evaluation
            history.add(message: reviewedMessage, result: evaluation)
        } catch let error as JevError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = JevError.unavailable.localizedDescription
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var traces: TraceStore
    @State private var confirmClear = false

    var body: some View {
        List {
            if history.records.isEmpty {
                ContentUnavailableView("No reviews yet", systemImage: "tray",
                                       description: Text("Manual AI analyses saved on this device will appear here."))
            }
            ForEach(history.records) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.timestamp, style: .date)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.message)
                        .font(.body)
                    Text("Jev yes: \(item.probability.formatted(.percent.precision(.fractionLength(1)))) · \(item.suggestedSTOP ? "Suggested STOP" : "No reply suggested")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Preview only · Nothing sent · Nothing deleted")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Review history")
        .toolbar {
            Button("Clear", role: .destructive) { confirmClear = true }
                .disabled(history.records.isEmpty && traces.traces.isEmpty)
        }
        .confirmationDialog("Delete local history and developer traces?", isPresented: $confirmClear) {
            Button("Clear all local history", role: .destructive) {
                history.clear()
                traces.clear()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var traces: TraceStore
    @EnvironmentObject private var account: GoogleAccountStore
    @AppStorage("setupComplete") private var setupComplete = false
    @State private var accountBusy = false
    @State private var accountError: String?
    @State private var agreeOwnKey = false
    @State private var enteredKey = ""
    @State private var keyIsSaved = KeychainVault.apiKey != nil
    @State private var keyError: String?
    @State private var developerTaps = 0
    @State private var confirmDeveloper = false
    @State private var confirmErase = false

    private func categoryBinding(_ category: Int) -> Binding<Bool> {
        Binding(
            get: { settings.value.categoryMask & category != 0 },
            set: { selected in
                if selected { settings.value.categoryMask |= category }
                else { settings.value.categoryMask &= ~category }
            }
        )
    }

    var body: some View {
        Form {
            if account.signedIn {
                Section("Google account") {
                    Label("Signed in with Google", systemImage: "checkmark.shield")
                    Text(account.subscriptionLabel).font(.subheadline).foregroundStyle(.secondary)
                    Button("Check subscription status") {
                        accountBusy = true
                        accountError = nil
                        Task {
                            defer { accountBusy = false }
                            do { try await account.checkAccount() }
                            catch { accountError = error.localizedDescription }
                        }
                    }.disabled(accountBusy)
                    if accountBusy { ProgressView() }
                    if let accountError { Text(accountError).foregroundStyle(.red) }
                    Text("Managed Jev access uses your existing active subscription. New subscriptions and Apple Pay are not available in this iOS beta.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Sign out", role: .destructive) { account.signOut() }
                }
            } else {
            Section {
                SecureField("TypeSafe API key", text: $enteredKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                Text(keyIsSaved ? "API key saved in iOS Keychain" : "No API key saved")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save BYOK key") { agreeOwnKey = true }
                    .disabled(enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove key", role: .destructive) {
                    KeychainVault.delete("typesafe-api-key")
                    account.ownKeyChanged()
                    keyIsSaved = false
                    enteredKey = ""
                }.disabled(!keyIsSaved)
                if let keyError { Text(keyError).foregroundStyle(.red) }
            } header: {
                Text("AI connection")
                    .onTapGesture {
                        developerTaps += 1
                        if developerTaps >= 7 { developerTaps = 0; confirmDeveloper = true }
                    }
            } footer: {
                Text("Your key stays in Keychain. TypeSafe's own retention and billing terms apply.")
            }
            }

            Section("Filter categories") {
                Toggle("Go vote reminders", isOn: categoryBinding(FilterSettings.vote))
                Toggle("Political campaign messages", isOn: categoryBinding(FilterSettings.political))
                Toggle("Marketing ads", isOn: categoryBinding(FilterSettings.marketing))
                Text("Enabled categories are combined into a single OR-based Jev question.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("AI confidence") {
                HStack {
                    Text("Minimum yes probability")
                    Spacer()
                    Text("\(Int(settings.value.threshold * 100))%").bold()
                }
                Slider(value: $settings.value.threshold, in: 0.5...1.0, step: 0.05)
                Text("Applies to manual Jev reviews, not the separate offline extension rules.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("iOS SMS filter extension") {
                Toggle("Enable conservative offline filtering", isOn: $settings.value.offlineFilteringEnabled)
                    .disabled(!settings.sharedStorageAvailable)
                Text("Also enable TextSentry in iPhone Settings → Apps → Messages → Unknown & Spam. Local rules only recognize explicit promotions/campaign language. They do not use your API key, extra prompt or AI threshold.")
                    .font(.caption).foregroundStyle(.secondary)
                if !settings.sharedStorageAvailable {
                    Text("Shared settings are unavailable. Automatic filtering cannot be enabled.")
                        .foregroundStyle(.red)
                }
            }

            if settings.value.developerModeEnabled {
                Section("Developer mode") {
                    NavigationLink("Developer tools") { DeveloperView() }
                }
            }

            Section("On-device privacy") {
                Button("Delete all local app data", role: .destructive) {
                    confirmErase = true
                }
                Text("Signs out, erases local credentials, manual history and developer traces; does not delete messages in Apple's Messages app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Using your own API key", isPresented: $agreeOwnKey, titleVisibility: .visible) {
            Button("Cancel", role: .cancel) {}
            Button("I understand and agree") {
                do {
                    try KeychainVault.setAPIKey(enteredKey)
                    account.ownKeyChanged()
                    enteredKey = ""
                    keyIsSaved = true
                    keyError = nil
                } catch { keyError = "Unable to store the key securely." }
            }
        } message: {
            Text("Messages are sent directly to TypeSafe using your own account. TextSentry's managed zero-data-retention protection does not apply. You are responsible for provider terms, retention agreements and charges.")
        }
        .alert("Enable developer mode?", isPresented: $confirmDeveloper) {
            Button("Enable") { settings.value.developerModeEnabled = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Developer traces can contain complete message text and model request/response JSON. They remain encrypted on this device.")
        }
        .confirmationDialog("Permanently delete local TextSentry data?", isPresented: $confirmErase) {
            Button("Delete local data", role: .destructive) {
                account.signOut()
                KeychainVault.delete("typesafe-api-key")
                account.ownKeyChanged()
                setupComplete = false
                keyIsSaved = false
                enteredKey = ""
                history.clear()
                traces.clear()
                settings.value = FilterSettings()
            }
        }
    }
}

struct DeveloperView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var traces: TraceStore

    var body: some View {
        Form {
            Section("Additional prompt restrictions") {
                TextEditor(text: $settings.value.extraRestrictions)
                    .frame(minHeight: 110)
                    .accessibilityLabel("Extra prompt restrictions")
                Text("Only narrows chosen categories; never bypasses safety checks. Maximum combined prompt: 3000 characters.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear additional prompt") { settings.value.extraRestrictions = "" }
            }
            Section("Raw request and response JSON") {
                Text("The last five successful manual TypeSafe requests. Credentials and authorization headers are excluded, but message contents ARE included.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(traces.traces) { trace in
                    DisclosureGroup {
                        Text("Request").bold()
                        Text(trace.requestJSON).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Response").bold()
                        Text(trace.responseJSON).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } label: {
                        Text(trace.timestamp, format: .dateTime.month().day().hour().minute())
                    }
                }
                Button("Clear traces", role: .destructive) { traces.clear() }
                    .disabled(traces.traces.isEmpty)
            }
            Section {
                Button("Disable developer mode", role: .destructive) {
                    settings.value.developerModeEnabled = false
                }
                Text("Disabling stops future traces. Existing traces remain until cleared.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Developer tools")
    }
}
