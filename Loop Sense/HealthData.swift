import Combine
import Foundation
import HealthKit

/// Reads Garmin data from Apple Health (M1). Nothing is written; everything stays on the phone.
nonisolated enum HealthReader {
    static var store: HKHealthStore { HealthSleep.store }

    static let quantityTypes: [HKQuantityTypeIdentifier] = [
        .restingHeartRate, .heartRate, .heartRateVariabilitySDNN, .respiratoryRate, .oxygenSaturation,
        .stepCount, .activeEnergyBurned, .appleExerciseTime,
    ]

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = Set(quantityTypes.map { HKQuantityType($0) })
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKObjectType.workoutType())
        return types
    }

    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Everything needed to build snapshots for `from...to`.
    static func inputs(from start: Date, to end: Date) async throws -> SnapshotBuilder.Inputs {
        // Sleep and overnight readings for the first day start the evening before.
        let from = start.addingTimeInterval(-6 * 3600)
        var inputs = SnapshotBuilder.Inputs()
        inputs.sleep = try await HealthSleep.rawIntervals(from: from, to: end)
        inputs.restingHR = try await samples(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: from, to: end)
        inputs.hrv = try await samples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: from, to: end)
        inputs.respiratoryRate = try await samples(.respiratoryRate, unit: .count().unitDivided(by: .minute()), from: from, to: end)
        inputs.oxygen = try await samples(.oxygenSaturation, unit: .percent(), from: from, to: end)
        inputs.steps = try await samples(.stepCount, unit: .count(), from: start, to: end)
        inputs.activeEnergy = try await samples(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        inputs.exerciseMinutes = try await samples(.appleExerciseTime, unit: .minute(), from: start, to: end)
        inputs.workouts = try await workouts(from: start, to: end)
        return inputs
    }

    /// Heart rate readings across a time span (for overnight charts, H3).
    static func heartRate(from start: Date, to end: Date) async throws -> [SnapshotBuilder.Sample] {
        try await samples(.heartRate, unit: .count().unitDivided(by: .minute()), from: start, to: end)
    }

    static func samples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws
        -> [SnapshotBuilder.Sample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let raw = try await descriptor.result(for: store)
        let samples = raw.map {
            SnapshotBuilder.Sample(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit),
                                   source: $0.sourceRevision.source.bundleIdentifier)
        }
        return SnapshotBuilder.preferGarmin(samples, source: \.source)
    }

    private static func workouts(from start: Date, to end: Date) async throws -> [(summary: WorkoutSummary, source: String)] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { w in
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            return (WorkoutSummary(type: w.workoutActivityType.name, start: w.startDate, duration: w.duration, energy: energy),
                    w.sourceRevision.source.bundleIdentifier)
        }
    }
}

/// Daily snapshots, kept up to date and saved on the phone. Backfills 30 days the first time, then
/// refreshes the last few days when the app opens and when Apple Health says new data arrived.
@MainActor
final class HealthDataStore: ObservableObject {
    /// Oldest first.
    @Published private(set) var snapshots: [DailySnapshot] = []
    @Published private(set) var isRefreshing = false
    /// Set once the person has been asked for Apple Health access (read access can't be checked).
    @Published private(set) var connected: Bool

    static let backfillDays = 30
    private static let refreshDays = 3
    private let fileURL: URL
    private var observing = false

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("health-snapshots.json")
        connected = UserDefaults.standard.bool(forKey: "healthDataConnected")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? SessionStore.decoder.decode([DailySnapshot].self, from: data) {
            snapshots = saved
        }
    }

    /// Asks for access, then backfills.
    func connect() async {
        guard HealthSleep.isAvailable else { return }
        try? await HealthReader.requestAccess()
        connected = true
        UserDefaults.standard.set(true, forKey: "healthDataConnected")
        UserDefaults.standard.set(true, forKey: "healthConnected")   // sleep stages in reports use the same access
        await refresh()
        startObserving()
    }

    /// Re-reads recent days (or the last 30 when there's nothing yet) and saves.
    func refresh() async {
        guard connected, HealthSleep.isAvailable, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let count = snapshots.isEmpty ? Self.backfillDays : Self.refreshDays
        let days = (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        guard let first = days.first,
              let end = calendar.date(byAdding: .day, value: 1, to: today),
              let inputs = try? await HealthReader.inputs(from: first, to: end) else { return }
        let fresh = SnapshotBuilder.build(days: days, from: inputs, calendar: calendar)
        var byDay = Dictionary(snapshots.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        for d in days { byDay[d] = nil }
        for s in fresh { byDay[s.day] = s }
        snapshots = byDay.values.sorted { $0.day < $1.day }
        if let data = try? SessionStore.encoder.encode(snapshots) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Refreshes when Garmin Connect syncs new data, even in the background (hourly at most).
    func startObserving() {
        guard connected, !observing, HealthSleep.isAvailable else { return }
        observing = true
        let watched: [HKSampleType] = [HKCategoryType(.sleepAnalysis), HKQuantityType(.restingHeartRate),
                                       HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.stepCount)]
        for type in watched {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                // HealthKit wants the handler called once the new data has been read.
                let done = CompletionBox(completion)
                Task { @MainActor in
                    await self?.refresh()
                    done.call()
                }
            }
            HealthReader.store.execute(query)
            HealthReader.store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    /// The snapshot for a day, if any.
    func snapshot(for day: Date, calendar: Calendar = .current) -> DailySnapshot? {
        let d = calendar.startOfDay(for: day)
        return snapshots.last { $0.day == d }
    }
}

/// Lets HealthKit's completion handler be called from the refresh task.
nonisolated private final class CompletionBox: @unchecked Sendable {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func call() { handler() }
}

private extension HKWorkoutActivityType {
    /// A short readable name for the common Garmin activities.
    nonisolated var name: String {
        switch self {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .yoga: "Yoga"
        case .highIntensityIntervalTraining: "HIIT"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .golf: "Golf"
        case .tennis: "Tennis"
        case .soccer: "Football"
        default: "Workout"
        }
    }
}
