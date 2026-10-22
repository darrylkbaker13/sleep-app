import SwiftUI

@main
struct LoopSenseApp: App {
    @StateObject private var store: SessionStore
    @StateObject private var recorder: NightRecorder

    init() {
        let store = SessionStore()
        _store = StateObject(wrappedValue: store)
        _recorder = StateObject(wrappedValue: NightRecorder(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(recorder)
                .font(.loop(.body))
                .tint(.loopAccent)
                .preferredColorScheme(.dark)
        }
    }
}
