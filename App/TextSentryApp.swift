import SwiftUI

@main
struct TextSentryApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var history = HistoryStore()
    @StateObject private var traces = TraceStore()
    @StateObject private var account = GoogleAccountStore()
    @AppStorage("setupComplete") private var setupComplete = false

    var body: some Scene {
        WindowGroup {
            Group {
                switch IosSetupGate.destination(signedIn: account.signedIn,
                                                hasOwnKey: account.hasBYOK,
                                                setupComplete: setupComplete) {
                case .login:
                    WelcomeView()
                case .filterSetup:
                    GuidedSetupView()
                case .home:
                    TabView {
                        NavigationStack { HomeView() }
                            .tabItem { Label("Home", systemImage: "shield.lefthalf.filled") }
                        NavigationStack { ManualReviewView() }
                            .tabItem { Label("Review", systemImage: "text.bubble") }
                        NavigationStack { HistoryView() }
                            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                        NavigationStack { SettingsView() }
                            .tabItem { Label("Settings", systemImage: "gearshape") }
                    }
                }
            }
            .tint(SentryColors.accent)
            .environmentObject(settings)
            .environmentObject(history)
            .environmentObject(traces)
            .environmentObject(account)
        }
    }
}
