import Foundation
import HealthKit

enum HealthKitServiceError: LocalizedError {
    case unavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data is unavailable on this device."
        case .authorizationDenied:
            return "Permission was denied. Enable Health access in Settings."
        }
    }
}

actor HealthKitService {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()
    private var calendar = Calendar(identifier: .gregorian)

    init() {
        calendar.timeZone = .current
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }

        var readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType()
        ]

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .oxygenSaturation,
            .restingHeartRate
        ]

        for identifier in quantityIdentifiers {
            if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                readTypes.insert(quantityType)
            }
        }

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleepType)
        }

        let success: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: granted)
            }
        }

        if !success {
            throw HealthKitServiceError.authorizationDenied
        }
    }

    func loadSleepDays(forLast days: Int) async throws -> [DaySleepRecord] {
        let todayStart = calendar.startOfDay(for: Date())
        guard let firstDay = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart),
              let queryEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return []
        }

        let sleepSamples = try await fetchSleepSamples(start: firstDay, end: queryEnd)

        var groupedSegments: [Date: [SleepSegment]] = [:]

        for sample in sleepSamples {
            guard let stage = SleepStage(healthKitValue: sample.value) else { continue }
            splitSampleAcrossDays(sample: sample, stage: stage, groupedSegments: &groupedSegments)
        }

        var dayRecords: [DaySleepRecord] = []

        for dayOffset in 0..<days {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            let segments = (groupedSegments[dayStart] ?? []).sorted { $0.startDate < $1.startDate }
            var record = DaySleepRecord(
                dayStart: dayStart,
                segments: segments,
                averageHeartRate: nil,
                averageHRV: nil,
                averageRespiratoryRate: nil,
                workoutMinutes: nil,
                averageSpO2: nil,
                restingHeartRate: nil,
                workouts: []
            )

            if !segments.isEmpty {
                let interval = DateInterval(start: segments.first?.startDate ?? dayStart, end: segments.last?.endDate ?? dayEnd)
                record.averageHeartRate = try await fetchAverageQuantity(
                    for: .heartRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    interval: interval
                )
                record.averageHRV = try await fetchAverageQuantity(
                    for: .heartRateVariabilitySDNN,
                    unit: HKUnit.secondUnit(with: .milli),
                    interval: interval
                )
                record.averageRespiratoryRate = try await fetchAverageQuantity(
                    for: .respiratoryRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    interval: interval
                )
                record.averageSpO2 = try await fetchAverageQuantity(
                    for: .oxygenSaturation,
                    unit: HKUnit.percent(),
                    interval: interval
                )
                // SpO2 comes as a fraction (0.0-1.0), convert to percentage
                if let spo2 = record.averageSpO2 {
                    record.averageSpO2 = (spo2 * 100).rounded(to: 1)
                }
            }

            record.restingHeartRate = try await fetchAverageQuantity(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                interval: DateInterval(start: dayStart, end: dayEnd)
            )

            let workoutDetails = try await fetchWorkoutDetails(start: dayStart, end: dayEnd)
            record.workouts = workoutDetails
            record.workoutMinutes = workoutDetails.reduce(0) { $0 + $1.durationMinutes }
            dayRecords.append(record)
        }

        return dayRecords
    }

    private func fetchSleepSamples(start: Date, end: Date) async throws -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let categorySamples = (samples as? [HKCategorySample]) ?? []
                continuation.resume(returning: categorySamples)
            }

            healthStore.execute(query)
        }
    }

    private func fetchAverageQuantity(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        interval: DateInterval
    ) async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let average = statistics?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: average)
            }

            healthStore.execute(query)
        }
    }

    private func fetchWorkoutDetails(start: Date, end: Date) async throws -> [WorkoutDetail] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let workoutType = HKObjectType.workoutType()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                let details = workouts.map { workout -> WorkoutDetail in
                    let durationMinutes = workout.duration / 60
                    let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    let intensity = Self.workoutIntensity(for: workout)

                    return WorkoutDetail(
                        activityType: Self.activityTypeName(workout.workoutActivityType),
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        durationMinutes: durationMinutes.rounded(to: 1),
                        intensity: intensity,
                        caloriesBurned: calories.map { $0.rounded(to: 0) }
                    )
                }
                continuation.resume(returning: details)
            }

            healthStore.execute(query)
        }
    }

    private static func workoutIntensity(for workout: HKWorkout) -> String {
        // Estimate intensity from calories per minute
        let durationMinutes = workout.duration / 60
        guard durationMinutes > 0,
              let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) else {
            return "Moderate"
        }

        let calPerMin = calories / durationMinutes
        if calPerMin >= 10 {
            return "High"
        } else if calPerMin >= 5 {
            return "Moderate"
        } else {
            return "Low"
        }
    }

    private static func activityTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        case .coreTraining: return "Core Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .pilates: return "Pilates"
        case .badminton: return "Badminton"
        case .tennis: return "Tennis"
        case .tableTennis: return "Table Tennis"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .cricket: return "Cricket"
        case .mixedCardio: return "Mixed Cardio"
        default: return "Workout"
        }
    }

    private func splitSampleAcrossDays(
        sample: HKCategorySample,
        stage: SleepStage,
        groupedSegments: inout [Date: [SleepSegment]]
    ) {
        var cursor = sample.startDate
        let sampleEnd = sample.endDate

        while cursor < sampleEnd {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }

            let segmentEnd = min(sampleEnd, nextDay)
            if cursor < segmentEnd {
                let segment = SleepSegment(startDate: cursor, endDate: segmentEnd, stage: stage)
                groupedSegments[dayStart, default: []].append(segment)
            }

            cursor = segmentEnd
        }
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
