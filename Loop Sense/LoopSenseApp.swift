import SwiftUI

@main
struct LoopSenseApp: App {
    @StateObject private var store: SessionStore
    @StateObject private var recorder: NightRecorder
    @StateObject private var labeller: EventLabeller
    @StateObject private var health = HealthDataStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = SessionStore()
        let recorder = NightRecorder(store: store)
        _store = StateObject(wrappedValue: store)
        _recorder = StateObject(wrappedValue: recorder)
        _labeller = StateObject(wrappedValue: EventLabeller(store: store, recorder: recorder))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(recorder)
                .environmentObject(labeller)
                .environmentObject(health)
                .task { health.startObserving() }
                .onChange(of: scenePhase) { _, phase in
                    // Pick up anything Garmin Connect synced while the app was closed.
                    if phase == .active { Task { await health.refresh() } }
                }
                .font(.loop(.body))
                .tint(.loopAccent)
                .preferredColorScheme(.dark)
        }
    }
}
