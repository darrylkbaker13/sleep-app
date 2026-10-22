import AVFoundation
import SwiftUI
import UIKit

/// Short first-run setup: what the app does, microphone access, phone placement and optional
/// Apple Health. Shown once after the splash; Skip or finishing sets `hasOnboarded`.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        ZStack {
            Color.loopMidnight.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip", action: onFinish)
                        .foregroundStyle(Color.loopSilver)
                        .opacity(page < pageCount - 1 ? 1 : 0)
                        .disabled(page == pageCount - 1)
                }
                .padding(.horizontal, 24)
                .frame(height: 44)

                TabView(selection: $page) {
                    WelcomePage().tag(0)
                    MicrophonePage().tag(1)
                    PlacementPage().tag(2)
                    HealthPage().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PageDots(count: pageCount, current: page)
                    .padding(.bottom, 20)

                Button {
                    if page < pageCount - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < pageCount - 1 ? "Continue" : "Start using Loop Sense")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.loopAccent)
                .foregroundStyle(Color.loopOnAccent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.loopAccent : Color.loopSilver.opacity(0.3))
                    .frame(width: i == current ? 20 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// Icon, title and body shared by every page, with optional controls underneath.
private struct OnboardingPage<Extra: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var extra: Extra

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.loopAccent)
                    .frame(height: 90)
                    .padding(.top, 40)
                Text(title)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .foregroundStyle(Color.loopSilver)
                    .multilineTextAlignment(.center)
                extra
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

extension OnboardingPage where Extra == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

private struct WelcomePage: View {
    var body: some View {
        OnboardingPage(icon: "moon.zzz.fill",
                       title: "Welcome to Loop Sense",
                       message: "Loop Sense listens to your bedroom while you sleep and shows you how noisy the night really was.") {
            VStack(alignment: .leading, spacing: 14) {
                Bullet(icon: "waveform", text: "Measures noise levels all night")
                Bullet(icon: "chart.xyaxis.line", text: "Compares your room with the WHO's sleep guidelines")
                Bullet(icon: "speaker.wave.2", text: "Finds the loud moments so you can play them back")
            }
            .padding(.top, 8)
        }
    }
}

private struct MicrophonePage: View {
    @State private var permission = AVAudioApplication.shared.recordPermission
    @Environment(\.openURL) private var openURL

    var body: some View {
        OnboardingPage(icon: "mic.fill",
                       title: "Allow the microphone",
                       message: "Loop Sense needs the microphone to measure how loud your room is. It only records while you're recording a night, and audio stays on your phone.") {
            switch permission {
            case .granted:
                Label("Microphone allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.loopAccent)
                    .padding(.top, 8)
            case .denied:
                VStack(spacing: 10) {
                    Text("Microphone access is off. Turn it on in Settings to record.")
                        .font(.footnote)
                        .foregroundStyle(Color.loopCoral)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            default:
                Button("Allow microphone") {
                    Task {
                        _ = await AVAudioApplication.requestRecordPermission()
                        permission = AVAudioApplication.shared.recordPermission
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
        }
    }
}

private struct PlacementPage: View {
    var body: some View {
        OnboardingPage(icon: "iphone.gen3.radiowaves.left.and.right",
                       title: "Set up your phone",
                       message: "A good spot makes the readings match what you hear.") {
            VStack(alignment: .leading, spacing: 14) {
                Bullet(icon: "powerplug.fill", text: "Plug it in. A full night of recording uses a lot of battery.")
                Bullet(icon: "bed.double.fill", text: "Place it near your head, on a bedside table, within about a metre of you.")
                Bullet(icon: "mic.fill", text: "Keep the microphone uncovered. Don't put it under a pillow or in a drawer.")
                Bullet(icon: "lock.fill", text: "You can lock your phone. Recording carries on in the background.")
            }
            .padding(.top, 8)
        }
    }
}

private struct HealthPage: View {
    @AppStorage("healthConnected") private var healthConnected = false
    @State private var errorText: String?

    var body: some View {
        OnboardingPage(icon: "heart.text.square.fill",
                       title: "Add your sleep stages",
                       message: "Optional. If your watch shares sleep with Apple Health (Garmin Connect can), Loop Sense shows how noise lined up with your light, deep and REM sleep.") {
            VStack(spacing: 10) {
                if healthConnected {
                    Label("Apple Health connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.loopAccent)
                } else if HealthSleep.isAvailable {
                    Button("Connect Apple Health") {
                        Task {
                            do {
                                try await HealthSleep.requestAccess()
                                healthConnected = true
                                errorText = nil
                            } catch {
                                errorText = "Couldn't connect to Apple Health: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    Text("You can also do this later from any night's report.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Apple Health isn't available on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(Color.loopRed)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 8)
        }
    }
}

private struct Bullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.loopAccent)
                .frame(width: 24)
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
