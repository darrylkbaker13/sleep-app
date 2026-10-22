import SwiftUI
import UIKit

/// Shown briefly when the app opens. Add an image named "SplashLogo" to Assets.xcassets to use
/// your own logo; without one, a Loop Sense wordmark is shown instead.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.loopMidnight.ignoresSafeArea()

            VStack(spacing: 20) {
                if let logo = UIImage(named: "SplashLogo") {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                } else {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.loopGold)
                    Text("Loop Sense")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.loopGold)
                }
                ProgressView()
                    .tint(Color.loopSilver)
                    .padding(.top, 12)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
    }
}

/// Shows the splash, then cross-fades into the app.
struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
        }
    }
}
