import SwiftUI

/// A short at-a-glance fact on the report, e.g. "Within WHO guideline". Tapping it shows `detail`.
nonisolated struct ReportChip: Identifiable, Hashable {
    enum Tone: Hashable { case good, warning, neutral }

    var id: String { text }
    /// SF Symbol name.
    let icon: String
    let text: String
    let tone: Tone
    /// Full explanation shown in a sheet, so nothing is lost by keeping the chip short.
    let detail: String
}

extension ReportChip.Tone {
    var color: Color {
        switch self {
        case .good: .loopGood
        case .warning: .loopWarn
        case .neutral: .loopSilver
        }
    }
}

/// A wrapping row of chips; tapping one opens its explanation.
struct ChipRow: View {
    let chips: [ReportChip]
    @State private var selected: ReportChip?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(chips) { chip in
                Button { selected = chip } label: {
                    Label(chip.text, systemImage: chip.icon)
                        .font(.loop(.subheadline))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(chip.tone.color)
                        .background(chip.tone.color.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows more detail")
            }
        }
        .sheet(item: $selected) { chip in
            ChipDetailSheet(chip: chip)
        }
    }
}

private struct ChipDetailSheet: View {
    let chip: ReportChip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(chip.text, systemImage: chip.icon)
                        .font(.loop(.title3))
                        .foregroundStyle(chip.tone.color)
                    Text(chip.detail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .loopBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.loopMidnight)
    }
}
