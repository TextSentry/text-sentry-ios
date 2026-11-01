import SwiftUI

@main
struct TextSentryApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var history = HistoryStore()
    @StateObject private var traces = TraceStore()

    var body: some Scene {
        WindowGroup {
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
            .tint(Color(red: 0.28, green: 0.38, blue: 0.94))
            .environmentObject(settings)
            .environmentObject(history)
            .environmentObject(traces)
        }
    }
}
