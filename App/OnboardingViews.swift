import Foundation

enum IosSetupGate {
    enum Destination: Equatable { case login, filterSetup, home }
    static func destination(signedIn: Bool, hasOwnKey: Bool, setupComplete: Bool) -> Destination {
        guard signedIn || hasOwnKey else { return .login }
        return setupComplete ? .home : .filterSetup
    }
}

import SwiftUI
import UIKit

enum SentryColors {
    static let navy = Color(red: 5/255, green: 14/255, blue: 32/255)
    static let ink = Color(red: 11/255, green: 23/255, blue: 48/255)
    static let accent = Color(red: 38/255, green: 215/255, blue: 238/255)
    static let paper = Color(red: 243/255, green: 247/255, blue: 1)
}

private struct BrandHeader: View {
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(SentryColors.accent)
                Text("TextSentry").font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(".").font(.system(size: 29, weight: .bold))
                    .foregroundStyle(SentryColors.accent)
            }
            Text(subtitle).font(.subheadline).foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(SentryColors.navy, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var account: GoogleAccountStore
    @State private var loading = false
    @State private var errorText: String?
    @State private var enteringKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandHeader(subtitle: "Stop sorting through political spam and marketing ads.")
                VStack(alignment: .leading, spacing: 14) {
                    Text("Get started").font(.title.bold())
                    Text("Sign in to use your TextSentry account. Purchases are not available on iOS yet.")
                        .foregroundStyle(.secondary)
                    Button {
                        loading = true
                        errorText = nil
                        Task {
                            defer { loading = false }
                            do { try await account.signIn() }
                            catch { errorText = error.localizedDescription }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("G").font(.title3.bold()).foregroundStyle(.blue)
                            Text("Sign in with Google").font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SentryColors.navy)
                    .disabled(loading)
                    if loading { ProgressView("Signing in…") }
                    if let errorText { Text(errorText).foregroundStyle(.red) }
                    Button("Skip sign-in and use your own API key") { enteringKey = true }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                Text("Privacy first · Your messages never go to TextSentry servers. iOS filtering uses local rules; manual AI review is optional.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(SentryColors.paper)
        .sheet(isPresented: $enteringKey) {
            NavigationStack { OwnKeyEntryView() }
        }
    }
}

struct OwnKeyEntryView: View {
    @EnvironmentObject private var account: GoogleAccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var confirm = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("TypeSafe API key") {
                SecureField("API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                Button("Continue") { confirm = true }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                Text("Your own API key uses your TypeSafe account, not TextSentry's managed zero-retention protection.")
                    .font(.subheadline)
            }
        }
        .navigationTitle("Use your own key")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .confirmationDialog("Using your own API key", isPresented: $confirm, titleVisibility: .visible) {
            Button("Cancel", role: .cancel) {}
            Button("I understand and agree") {
                do {
                    try KeychainVault.setAPIKey(key)
                    account.ownKeyChanged()
                    key = ""
                    dismiss()
                } catch { errorText = "Unable to store your API key securely." }
            }
        } message: {
            Text("Messages are sent directly to TypeSafe under your account. TextSentry's managed zero-data-retention guardrail does not apply. You are responsible for your provider's retention terms, agreements and usage charges.")
        }
        .alert("Key error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }
}

struct GuidedSetupView: View {
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage("setupComplete") private var setupComplete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandHeader(subtitle: "Set up iPhone message filtering")
                Text("1. Choose local filtering").font(.title3.bold())
                Text("TextSentry's iPhone extension can sort unknown-sender SMS/MMS using conservative on-device rules. It cannot use Jev automatically or send STOP.")
                Toggle("Enable local filtering", isOn: $settings.value.offlineFilteringEnabled)
                    .disabled(!settings.sharedStorageAvailable)
                Text("2. Enable TextSentry in iPhone Settings").font(.title3.bold())
                Text("Open Settings → Apps → Messages → Unknown & Spam. Select TextSentry as your SMS filter. This step must be done in Apple's Settings.")
                if !settings.sharedStorageAvailable {
                    Text("App Group settings are unavailable. Local filtering will stay disabled.")
                        .foregroundStyle(.red)
                }
                Button("Continue to TextSentry") { setupComplete = true }
                    .buttonStyle(.borderedProminent)
                    .tint(SentryColors.navy)
                    .frame(maxWidth: .infinity)
                Text("You can still review pasted messages manually. No automatic STOP replies or SMS deletion on iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(SentryColors.paper)
    }
}
