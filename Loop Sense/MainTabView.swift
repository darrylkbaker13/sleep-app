import SwiftUI
import UIKit

/// The app's four tabs. Sleep is the default.
struct MainTabView: View {
    enum Tab: Hashable { case sleep, health, trends, settings }

    @State private var selection: Tab = .sleep

    init() {
        // Dark tab bar to match the app; the selected tab is tinted loopAccent by the app-wide tint.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.loopMidnight)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selection) {
            ContentView()
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
                .tag(Tab.sleep)

            HealthTabView()
                .tabItem { Label("Health", systemImage: "waveform.path.ecg") }
                .tag(Tab.health)

            NavigationStack { TrendsView() }
                .tabItem { Label("Trends", systemImage: "chart.bar.fill") }
                .tag(Tab.trends)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Color.loopAccent)
    }
}

/// Placeholder until the Garmin dashboard (H2) is built.
struct HealthTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Health", systemImage: "waveform.path.ecg")
            } description: {
                Text("Your Garmin sleep and body data from Apple Health will appear here.")
            }
            .loopBackground()
        }
    }
}
