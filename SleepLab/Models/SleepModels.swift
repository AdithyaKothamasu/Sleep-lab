import Foundation
import HealthKit

enum SleepStage: String, CaseIterable, Identifiable, Hashable {
    case inBed
    case awake
    case core
    case rem
    case deep

    var id: String { rawValue }

    var chartValue: Double {
        switch self {
        case .inBed:
            return 0
        case .deep:
            return 1
        case .core:
            return 2
        case .rem:
            return 3
        case .awake:
            return 4
        }
    }

    var displayName: String {
        switch self {
        case .inBed:
            return "In Bed"
        case .awake:
            return "Awake"
        case .core:
            return "Core"
        case .rem:
            return "REM"
        case .deep:
            return "Deep"
        }
    }

    var normalizedForHypnogram: SleepStage {
        self == .inBed ? .core : self
    }

    var appleRow: Double {
        switch normalizedForHypnogram {
        case .deep:
            return 0
        case .core:
            return 1
        case .rem:
            return 2
        case .awake:
            return 3
        case .inBed:
            return 1
        }
    }

    static var appleAxisValues: [Double] {
        [0, 1, 2, 3]
    }

    static var comparisonStages: [SleepStage] {
        [.awake, .rem, .core, .deep]
    }

    static func stage(forAppleRow value: Double) -> SleepStage? {
        switch value {
        case 0:
            return .deep
        case 1:
            return .core
        case 2:
            return .rem
        case 3:
            return .awake
        default:
            return nil
        }
    }

    init?(healthKitValue: Int) {
        switch healthKitValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            self = .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            self = .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            self = .core
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            self = .rem
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            self = .deep
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            self = .core
        default:
            return nil
        }
    }

    static func stage(forChartValue value: Double) -> SleepStage? {
        allCases.first(where: { abs($0.chartValue - value) < 0.1 })
    }
}

enum ComparisonAlignment: String, CaseIterable, Identifiable {
    case clockTime
    case sleepStart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clockTime:
            return "Clock Time"
        case .sleepStart:
            return "Sleep Start"
        }
    }
}

struct SleepSegment: Identifiable, Hashable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let stage: SleepStage

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}

struct SleepChartPoint: Identifiable, Hashable {
    let id = UUID()
    let x: Double
    let stage: SleepStage
}

struct HypnogramRange: Identifiable, Hashable {
    let id = UUID()
    let startHour: Double
    let endHour: Double
    let stage: SleepStage
}

struct HypnogramTransition: Identifiable, Hashable {
    let id = UUID()
    let hour: Double
    let fromStage: SleepStage
    let toStage: SleepStage

    var startRow: Double {
        min(fromStage.appleRow, toStage.appleRow)
    }

    var endRow: Double {
        max(fromStage.appleRow, toStage.appleRow)
    }
}

struct WorkoutDetail: Identifiable, Hashable {
    let id = UUID()
    let activityType: String
    let startDate: Date
    let endDate: Date
    let durationMinutes: Double
    let intensity: String
    let caloriesBurned: Double?
}

struct DaySleepRecord: Identifiable, Hashable {
    let dayStart: Date
    var segments: [SleepSegment]
    var averageHeartRate: Double?
    var averageHRV: Double?
    var averageRespiratoryRate: Double?
    var workoutMinutes: Double?
    var averageSpO2: Double?
    var restingHeartRate: Double?
    var workouts: [WorkoutDetail]

    var id: Date { dayStart }

    var firstSegmentStart: Date? {
        segments.map(\.startDate).min()
    }

    var lastSegmentEnd: Date? {
        segments.map(\.endDate).max()
    }

    var totalSleepDuration: TimeInterval {
        segments
            .filter { $0.stage != .awake }
            .reduce(0) { $0 + $1.duration }
    }

    var chartWidth: Double {
        let span = chartSpan / 3600
        return max(260, span * 72)
    }

    var chartSpan: TimeInterval {
        guard let first = firstSegmentStart, let last = lastSegmentEnd else {
            return 4 * 3600
        }
        return max(last.timeIntervalSince(first), 4 * 3600)
    }

    var dayLabel: String {
        dayStart.formatted(.dateTime.month(.abbreviated).day())
    }

    func chartPoints(alignment: ComparisonAlignment) -> [SleepChartPoint] {
        let orderedSegments = segments.sorted { $0.startDate < $1.startDate }
        guard !orderedSegments.isEmpty else { return [] }

        let baseline = alignment == .sleepStart ? orderedSegments.first?.startDate : dayStart
        guard let baseline else { return [] }

        return orderedSegments.flatMap { segment in
            let startX = max(segment.startDate.timeIntervalSince(baseline) / 3600, 0)
            let endX = max(segment.endDate.timeIntervalSince(baseline) / 3600, 0)

            return [
                SleepChartPoint(x: startX, stage: segment.stage),
                SleepChartPoint(x: endX, stage: segment.stage)
            ]
        }
    }

    func stage(atHour hour: Double, alignment: ComparisonAlignment) -> SleepStage? {
        guard !segments.isEmpty else { return nil }

        let baseline: Date
        switch alignment {
        case .clockTime:
            baseline = dayStart
        case .sleepStart:
            guard let firstSegmentStart else { return nil }
            baseline = firstSegmentStart
        }

        let date = baseline.addingTimeInterval(hour * 3600)

        for segment in segments where segment.startDate <= date && date < segment.endDate {
            return segment.stage
        }

        return nil
    }

    func hypnogramRanges(alignment: ComparisonAlignment) -> [HypnogramRange] {
        let orderedSegments = segments.sorted { $0.startDate < $1.startDate }
        guard !orderedSegments.isEmpty else { return [] }

        let baseline: Date?
        switch alignment {
        case .sleepStart:
            baseline = orderedSegments.first?.startDate
        case .clockTime:
            baseline = orderedSegments.first?.startDate
        }
        guard let baseline else { return [] }

        var ranges: [HypnogramRange] = []

        for segment in orderedSegments {
            let stage = segment.stage.normalizedForHypnogram
            let startHour = max(segment.startDate.timeIntervalSince(baseline) / 3600, 0)
            let endHour = max(segment.endDate.timeIntervalSince(baseline) / 3600, 0)

            guard endHour > startHour else { continue }

            if let last = ranges.last,
               last.stage == stage,
               abs(last.endHour - startHour) < 0.01 {
                ranges[ranges.count - 1] = HypnogramRange(
                    startHour: last.startHour,
                    endHour: endHour,
                    stage: stage
                )
            } else {
                ranges.append(
                    HypnogramRange(
                        startHour: startHour,
                        endHour: endHour,
                        stage: stage
                    )
                )
            }
        }

        return ranges
    }

    func hypnogramTransitions(alignment: ComparisonAlignment) -> [HypnogramTransition] {
        let ranges = hypnogramRanges(alignment: alignment)
        guard ranges.count >= 2 else { return [] }

        var transitions: [HypnogramTransition] = []

        for index in 1..<ranges.count {
            let previous = ranges[index - 1]
            let current = ranges[index]

            guard previous.stage != current.stage else { continue }
            guard abs(current.startHour - previous.endHour) <= 0.35 else { continue }

            transitions.append(
                HypnogramTransition(
                    hour: current.startHour,
                    fromStage: previous.stage,
                    toStage: current.stage
                )
            )
        }

        return transitions
    }

    func hypnogramMaxHour(alignment: ComparisonAlignment) -> Double {
        hypnogramRanges(alignment: alignment)
            .map(\.endHour)
            .max() ?? 0
    }

    func hypnogramMinHour(alignment: ComparisonAlignment) -> Double {
        hypnogramRanges(alignment: alignment)
            .map(\.startHour)
            .min() ?? 0
    }

    /// The baseline date used for hypnogram hour calculations.
    func hypnogramBaseline(alignment: ComparisonAlignment) -> Date {
        switch alignment {
        case .sleepStart, .clockTime:
            return firstSegmentStart ?? dayStart
        }
    }
}

enum InsightConfidence: String, Codable, CaseIterable {
    case low
    case medium
    case high
}

struct PatternEvidence: Identifiable, Hashable, Codable {
    let id: String
    let dayLabel: String
    let metric: String
    let value: String

    init(dayLabel: String, metric: String, value: String) {
        self.id = "\(dayLabel)-\(metric)-\(value)"
        self.dayLabel = dayLabel
        self.metric = metric
        self.value = value
    }
}

struct DeterministicInsight: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let summary: String
    let confidence: InsightConfidence
    let evidence: [PatternEvidence]
}

struct AIInsight: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let summary: String
    let confidence: InsightConfidence
    let evidence: [String]

    init(id: String = UUID().uuidString, title: String, summary: String, confidence: InsightConfidence, evidence: [String]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.confidence = confidence
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case confidence
        case evidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        confidence = try container.decode(InsightConfidence.self, forKey: .confidence)
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(title)-\(summary)".lowercased()
    }
}

struct AIInsightResponse: Hashable, Codable {
    let aiSummary: String
    let insights: [AIInsight]
    let caveats: [String]
    let noClearPattern: Bool
}

enum PatternAIStatus: Hashable {
    case disabled
    case loading
    case ready
    case failed(String)
    case unavailable
}

struct PatternAnalysisResult: Hashable {
    var deterministicInsights: [DeterministicInsight]
    var aiSummary: String?
    var aiInsights: [AIInsight]
    var caveats: [String]
    var noClearPattern: Bool
    var aiStatus: PatternAIStatus
    var analyzedAt: Date
}

struct PatternAnalysisPayload: Codable {
    let selectedDates: [PatternDayPayload]
}

struct PatternDayPayload: Codable {
    let dayLabel: String
    let dayStartISO: String
    let sleep: PatternSleepMetricsPayload
    let stageDurations: [PatternStageDurationPayload]
    let segments: [PatternSleepSegmentPayload]
    let events: [PatternEventPayload]
}

struct PatternSleepMetricsPayload: Codable {
    let totalSleepHours: Double
    let awakeningCount: Int
    let mainSleepStartISO: String?
    let mainSleepEndISO: String?
    let averageHeartRate: Double?
    let averageHRV: Double?
    let averageRespiratoryRate: Double?
    let workoutMinutes: Double?
    let averageSpO2: Double?
    let restingHeartRate: Double?
}

struct PatternStageDurationPayload: Codable {
    let stage: String
    let hours: Double
}

struct PatternSleepSegmentPayload: Codable {
    let stage: String
    let startISO: String
    let endISO: String
    let durationMinutes: Double
}

struct PatternEventPayload: Codable {
    let name: String
    let timestampISO: String
    let note: String?
    let minutesBeforeMainSleepStart: Double?
}
