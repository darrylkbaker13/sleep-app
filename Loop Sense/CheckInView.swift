import SwiftUI

/// Rating labels and tags for the morning check-in.
nonisolated enum SleepNotes {
    static let defaultTags = ["Window open", "Fan or AC on", "Partner away", "Alcohol", "Late caffeine", "Ill"]
    static let otherEarplugs = "Other earplugs"
    /// Models offered when tagging earplugs: Loop's sleep-suitable adult models, then anything else.
    static let earplugChoices = LoopModel.all.filter { $0.goodForSleep && !$0.kidsOnly }.map(\.name) + [otherEarplugs]

    static func label(forRating rating: Int) -> String {
        ["Awful", "Poor", "OK", "Good", "Great"][max(1, min(5, rating)) - 1]
    }
}

/// "How did you sleep?" sheet, shown when a recording stops and from a night's report.
struct CheckInView: View {
    /// Called with the updated night, or nil if skipped.
    let onDone: (SleepSession?) -> Void

    @State private var session: SleepSession
    @State private var rating: Int?
    @State private var tags: Set<String>
    @State private var earplugs: String?
    @State private var newTag = ""
    /// User-added tags, newline-separated.
    @AppStorage("customSleepTags") private var customTagsText = ""

    init(session: SleepSession, onDone: @escaping (SleepSession?) -> Void) {
        self.onDone = onDone
        _session = State(initialValue: session)
        _rating = State(initialValue: session.rating)
        _tags = State(initialValue: Set(session.tags ?? []))
        _earplugs = State(initialValue: session.earplugs)
    }

    private var customTags: [String] {
        customTagsText.split(separator: "\n").map(String.init)
    }

    /// Default and custom tags, plus any old tags on this night that are no longer in either list.
    private var allTags: [String] {
        let known = SleepNotes.defaultTags + customTags
        return known + tags.filter { !known.contains($0) }.sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How did you sleep?").font(.loop(.title2))
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { value in
                                ratingButton(value)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Anything different last night?").font(.loop(.headline))
                        FlowLayout(spacing: 8) {
                            Chip(title: "Earplugs", isOn: earplugs != nil) {
                                earplugs = earplugs == nil ? SleepNotes.earplugChoices.first : nil
                            }
                            ForEach(allTags, id: \.self) { tag in
                                Chip(title: tag, isOn: tags.contains(tag)) {
                                    if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                                }
                            }
                        }
                        if earplugs != nil {
                            Picker("Which earplugs?", selection: Binding(
                                get: { earplugs ?? SleepNotes.otherEarplugs },
                                set: { earplugs = $0 })) {
                                ForEach(SleepNotes.earplugChoices, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.loopAccent)
                        }
                        HStack {
                            TextField("Add your own tag", text: $newTag)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit(addTag)
                            Button("Add", action: addTag)
                                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding()
            }
            .loopBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onDone(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.loopMidnight)
    }

    private func ratingButton(_ value: Int) -> some View {
        let selected = rating == value
        return Button {
            rating = selected ? nil : value
        } label: {
            VStack(spacing: 4) {
                Text("\(value)").font(.loop(.title2)).monospacedDigit()
                Text(SleepNotes.label(forRating: value)).font(.loop(.caption2))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(selected ? Color.loopOnAccent : Color.primary)
            .background(selected ? Color.loopAccent : Color.loopSurface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value), \(SleepNotes.label(forRating: value))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        newTag = ""
        guard !tag.isEmpty, tag.caseInsensitiveCompare("Earplugs") != .orderedSame else { return }
        if !allTags.contains(tag) {
            customTagsText = (customTags + [tag]).joined(separator: "\n")
        }
        tags.insert(tag)
    }

    private func save() {
        session.rating = rating
        session.tags = allTags.filter(tags.contains)
        session.earplugs = earplugs
        onDone(session)
    }
}

private struct Chip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.loop(.subheadline))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isOn ? Color.loopOnAccent : Color.primary)
                .background(isOn ? Color.loopAccent : Color.loopSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Lays children out in rows, wrapping to the next line when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// The check-in shown in a night's report, with an Edit button.
struct SleepNotesCard: View {
    let session: SleepSession
    let onEdit: () -> Void

    var body: some View {
        Card("How you slept") {
            let notes = (session.earplugs.map { [$0] } ?? []) + (session.tags ?? [])
            if session.rating == nil, notes.isEmpty {
                Text("Add how the night felt and anything that was different, like a window open or earplugs.")
                    .foregroundStyle(.secondary)
            } else {
                if let rating = session.rating {
                    Text("\(rating)/5 · \(SleepNotes.label(forRating: rating))")
                        .font(.loop(.title3))
                }
                if !notes.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(notes, id: \.self) { note in
                            Text(note)
                                .font(.loop(.caption))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.loopMidnight, in: Capsule())
                        }
                    }
                }
            }
            Button(session.rating == nil && notes.isEmpty ? "Add check-in" : "Edit", action: onEdit)
                .foregroundStyle(Color.loopAccent)
        }
    }
}
