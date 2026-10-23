import SwiftUI

@main
struct LoopSenseApp: App {
    @StateObject private var store: SessionStore
    @StateObject private var recorder: NightRecorder
    @StateObject private var labeller: EventLabeller

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
                .font(.loop(.body))
                .tint(.loopAccent)
                .preferredColorScheme(.dark)
        }
    }
}
