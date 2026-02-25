import CryptoKit
import Foundation
import Security

@MainActor
final class SleepLabViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case requestingAuthorization
        case loading
        case ready
        case denied
        case failed
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var sleepDays: [DaySleepRecord] = []
    @Published private(set) var events: [BehaviorTag] = []
    @Published private(set) var selectedDayIDs: Set<Date> = []
    @Published var comparisonAlignment: ComparisonAlignment = .sleepStart
    @Published private(set) var errorMessage: String?

    @Published private(set) var patternResultBySelectionKey: [String: PatternAnalysisResult] = [:]
    @Published private(set) var isAnalyzingPatterns = false
    @Published private(set) var patternErrorMessage: String?

    private let healthKitService: HealthKitService
    private let behaviorRepository: BehaviorRepository
    private let deterministicPatternEngine: DeterministicPatternEngine
    private let patternAPIService: PatternAPIService

    private static let healthAuthCompletedKey = "healthAuthorizationCompleted"

    private var hasCompletedHealthAuth: Bool {
        get { UserDefaults.standard.bool(forKey: Self.healthAuthCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.healthAuthCompletedKey) }
    }

    private var calendar = Calendar(identifier: .gregorian)

    init(
        healthKitService: HealthKitService,
        behaviorRepository: BehaviorRepository,
        deterministicPatternEngine: DeterministicPatternEngine = DeterministicPatternEngine(),
        patternAPIService: PatternAPIService = PatternAPIService()
    ) {
        self.healthKitService = healthKitService
        self.behaviorRepository = behaviorRepository
        self.deterministicPatternEngine = deterministicPatternEngine
        self.patternAPIService = patternAPIService
        calendar.timeZone = .current
    }

    var selectedDays: [DaySleepRecord] {
        sleepDays
            .filter { selectedDayIDs.contains($0.id) }
            .sorted { $0.dayStart > $1.dayStart }
    }

    var canCompare: Bool {
        selectedDayIDs.count >= 2
    }

    func prepareStores() {
        do {
            try behaviorRepository.seedDefaultTagsIfNeeded()
            events = try behaviorRepository.fetchTags()
        } catch {
            errorMessage = "Failed to initialize event types."
        }
    }

    func checkAndLoadIfAuthorized() {
        guard loadState == .idle else { return }

        // If the user has previously completed the authorization flow,
        // skip the permission screen and load data directly.
        if hasCompletedHealthAuth {
            loadState = .loading
            Task {
                do {
                    let days = try await healthKitService.loadSleepDays(forLast: 30)
                    sleepDays = days
                    patternResultBySelectionKey.removeAll()
                    loadState = .ready
                } catch {
                    // If loading fails, reset the flag so the permission screen
                    // is shown again for the user to re-authorize
                    hasCompletedHealthAuth = false
                    loadState = .idle
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func requestAccessAndLoadTimeline() {
        guard loadState != .loading && loadState != .requestingAuthorization else { return }

        loadState = .requestingAuthorization
        errorMessage = nil

        Task {
            do {
                try await healthKitService.requestAuthorization()
                hasCompletedHealthAuth = true
                loadState = .loading

                let days = try await healthKitService.loadSleepDays(forLast: 30)

                sleepDays = days
                patternResultBySelectionKey.removeAll()
                if selectedDayIDs.count > 5 {
                    selectedDayIDs = Set(selectedDayIDs.prefix(5))
                }
                loadState = .ready
            } catch let error as HealthKitServiceError {
                switch error {
                case .authorizationDenied:
                    hasCompletedHealthAuth = true
                    loadState = .denied
                    errorMessage = error.localizedDescription
                case .unavailable:
                    loadState = .failed
                    errorMessage = error.localizedDescription
                }
            } catch {
                loadState = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshTimeline() {
        guard loadState == .ready else { return }

        loadState = .loading
        Task {
            do {
                sleepDays = try await healthKitService.loadSleepDays(forLast: 30)
                patternResultBySelectionKey.removeAll()
                loadState = .ready
            } catch {
                loadState = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleSelection(for day: DaySleepRecord) {
        if selectedDayIDs.contains(day.id) {
            selectedDayIDs.remove(day.id)
            return
        }

        guard selectedDayIDs.count < 5 else { return }
        selectedDayIDs.insert(day.id)
    }

    func clearSelection() {
        selectedDayIDs.removeAll()
    }

    func logs(for dayStart: Date) -> [DayBehaviorLog] {
        (try? behaviorRepository.fetchLogs(for: dayStart)) ?? []
    }

    func logs(forSleepDay dayStart: Date) -> [DayBehaviorLog] {
        (try? behaviorRepository.fetchLogs(for: priorEventDay(forSleepDay: dayStart))) ?? []
    }

    func addCustomTag(name: String, colorHex: String) {
        do {
            try behaviorRepository.addCustomTag(name: name, colorHex: colorHex)
            events = try behaviorRepository.fetchTags()
        } catch {
            errorMessage = "Could not save event type."
        }
    }

    func addLog(for dayStart: Date, tagName: String, note: String?, eventTime: Date) {
        do {
            try behaviorRepository.addLog(for: dayStart, tagName: tagName, note: note, eventTime: eventTime)
            patternResultBySelectionKey.removeAll()
        } catch {
            errorMessage = "Could not save event."
        }
    }

    func addLog(forSleepDay dayStart: Date, tagName: String, note: String?, eventTime: Date) {
        do {
            try behaviorRepository.addLog(
                for: priorEventDay(forSleepDay: dayStart),
                tagName: tagName,
                note: note,
                eventTime: eventTime
            )
            patternResultBySelectionKey.removeAll()
        } catch {
            errorMessage = "Could not save event."
        }
    }

    func deleteLog(_ log: DayBehaviorLog) {
        do {
            try behaviorRepository.deleteLog(id: log.id)
            patternResultBySelectionKey.removeAll()
        } catch {
            errorMessage = "Could not delete event."
        }
    }

    func priorEventDay(forSleepDay dayStart: Date) -> Date {
        let normalized = calendar.startOfDay(for: dayStart)
        return calendar.date(byAdding: .day, value: -1, to: normalized) ?? normalized
    }

    /// Logs recorded for today's calendar date.
    var todayLogs: [DayBehaviorLog] {
        let today = calendar.startOfDay(for: Date())
        return (try? behaviorRepository.fetchLogs(for: today)) ?? []
    }

    /// True when an existing sleep-day card already covers today's events
    /// (meaning the standalone "Today" card should be hidden).
    var isTodayCoveredBySleepDay: Bool {
        let today = calendar.startOfDay(for: Date())
        return sleepDays.contains { priorEventDay(forSleepDay: $0.dayStart) == today }
    }

    func patternSelectionKey(for days: [DaySleepRecord]) -> String {
        days
            .map(\.dayStart)
            .sorted()
            .map { PatternFormatters.isoFormatter.string(from: $0) }
            .joined(separator: "|")
    }

    func patternResult(for days: [DaySleepRecord]) -> PatternAnalysisResult? {
        patternResultBySelectionKey[patternSelectionKey(for: days)]
    }

    func analyzePatterns(for days: [DaySleepRecord], includeAIInsights: Bool) async {
        guard !days.isEmpty else { return }

        let orderedDays = days.sorted { $0.dayStart > $1.dayStart }
        let logsBySleepDay = Dictionary(uniqueKeysWithValues: orderedDays.map { ($0.dayStart, logs(forSleepDay: $0.dayStart)) })
        let deterministicInsights = deterministicPatternEngine.analyze(days: orderedDays, logsBySleepDay: logsBySleepDay)

        let key = patternSelectionKey(for: orderedDays)

        var result = PatternAnalysisResult(
            deterministicInsights: deterministicInsights,
            aiSummary: nil,
            aiInsights: [],
            caveats: [],
            noClearPattern: deterministicInsights.count <= 1,
            aiStatus: includeAIInsights ? .loading : .disabled,
            analyzedAt: Date()
        )

        patternResultBySelectionKey[key] = result
        patternErrorMessage = nil

        guard includeAIInsights else {
            return
        }

        isAnalyzingPatterns = true
        defer { isAnalyzingPatterns = false }

        guard await patternAPIService.isConfigured else {
            result.aiStatus = .unavailable
            result.caveats = ["AI endpoint is not configured. Add PATTERN_API_BASE_URL in Info.plist."]
            patternResultBySelectionKey[key] = result
            return
        }

        do {
            let payload = buildPatternPayload(days: orderedDays, logsBySleepDay: logsBySleepDay)
            let aiResponse = try await patternAPIService.analyze(payload: payload)
            result.aiSummary = aiResponse.aiSummary
            result.aiInsights = aiResponse.insights
            result.caveats = aiResponse.caveats
            result.noClearPattern = aiResponse.noClearPattern
            result.aiStatus = .ready
            result.analyzedAt = Date()
            patternResultBySelectionKey[key] = result
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "AI pattern analysis failed."
            result.aiStatus = .failed(message)
            result.caveats = [message]
            result.analyzedAt = Date()
            patternErrorMessage = message
            patternResultBySelectionKey[key] = result
        }
    }

    private func buildPatternPayload(days: [DaySleepRecord], logsBySleepDay: [Date: [DayBehaviorLog]]) -> PatternAnalysisPayload {
        let dayPayloads = days.map { day -> PatternDayPayload in
            let mainSleepWindow = PatternMath.mainSleepWindow(for: day)
            let stageDurations = SleepStage.allCases.map {
                PatternStageDurationPayload(
                    stage: $0.rawValue,
                    hours: PatternMath.rawDurationHours(for: $0, in: day)
                )
            }

            let segments = day.segments
                .sorted { $0.startDate < $1.startDate }
                .map { segment in
                    PatternSleepSegmentPayload(
                        stage: segment.stage.normalizedForHypnogram.rawValue,
                        startISO: PatternFormatters.isoFormatter.string(from: segment.startDate),
                        endISO: PatternFormatters.isoFormatter.string(from: segment.endDate),
                        durationMinutes: segment.duration / 60
                    )
                }

            let logs = (logsBySleepDay[day.dayStart] ?? []).sorted { $0.loggedAt < $1.loggedAt }
            let events = logs.map { log -> PatternEventPayload in
                let minutesBeforeSleep: Double?
                if let mainSleepStart = mainSleepWindow?.start {
                    minutesBeforeSleep = mainSleepStart.timeIntervalSince(log.loggedAt) / 60
                } else {
                    minutesBeforeSleep = nil
                }

                return PatternEventPayload(
                    name: log.tagName,
                    timestampISO: PatternFormatters.isoFormatter.string(from: log.loggedAt),
                    note: log.note,
                    minutesBeforeMainSleepStart: minutesBeforeSleep
                )
            }

            return PatternDayPayload(
                dayLabel: day.dayStart.formatted(.dateTime.month(.abbreviated).day()),
                dayStartISO: PatternFormatters.isoFormatter.string(from: day.dayStart),
                sleep: PatternSleepMetricsPayload(
                    totalSleepHours: day.totalSleepDuration / 3600,
                    awakeningCount: PatternMath.awakeSegmentCount(for: day),
                    mainSleepStartISO: mainSleepWindow.map { PatternFormatters.isoFormatter.string(from: $0.start) },
                    mainSleepEndISO: mainSleepWindow.map { PatternFormatters.isoFormatter.string(from: $0.end) },
                    averageHeartRate: day.averageHeartRate,
                    averageHRV: day.averageHRV,
                    averageRespiratoryRate: day.averageRespiratoryRate,
                    workoutMinutes: day.workoutMinutes
                ),
                stageDurations: stageDurations,
                segments: segments,
                events: events
            )
        }

        return PatternAnalysisPayload(selectedDates: dayPayloads)
    }
}

private enum PatternFormatters {
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private enum PatternMath {
    static func mainSleepWindow(for day: DaySleepRecord) -> (start: Date, end: Date)? {
        let ordered = day.segments.sorted { $0.startDate < $1.startDate }
        guard !ordered.isEmpty else { return nil }

        struct Window {
            var start: Date
            var end: Date
            var duration: TimeInterval
        }

        var windows: [Window] = []
        var current = Window(start: ordered[0].startDate, end: ordered[0].endDate, duration: ordered[0].duration)

        for segment in ordered.dropFirst() {
            let gap = segment.startDate.timeIntervalSince(current.end)
            if gap <= 45 * 60 {
                current.end = max(current.end, segment.endDate)
                current.duration += segment.duration
            } else {
                windows.append(current)
                current = Window(start: segment.startDate, end: segment.endDate, duration: segment.duration)
            }
        }

        windows.append(current)

        guard let longest = windows.max(by: { $0.duration < $1.duration }) else {
            return nil
        }

        return (start: longest.start, end: longest.end)
    }

    static func durationHours(for stage: SleepStage, in day: DaySleepRecord) -> Double {
        let seconds = day.segments.reduce(0.0) { partial, segment in
            guard segment.stage.normalizedForHypnogram == stage else { return partial }
            return partial + segment.duration
        }
        return seconds / 3600
    }

    static func rawDurationHours(for stage: SleepStage, in day: DaySleepRecord) -> Double {
        let seconds = day.segments.reduce(0.0) { partial, segment in
            guard segment.stage == stage else { return partial }
            return partial + segment.duration
        }
        return seconds / 3600
    }

    static func awakeMinutes(for day: DaySleepRecord) -> Double {
        day.segments
            .filter { $0.stage.normalizedForHypnogram == .awake }
            .reduce(0.0) { $0 + $1.duration / 60 }
    }

    static func awakeSegmentCount(for day: DaySleepRecord) -> Int {
        day.segments.filter { $0.stage.normalizedForHypnogram == .awake }.count
    }
}

struct DeterministicPatternEngine {
    func analyze(days: [DaySleepRecord], logsBySleepDay: [Date: [DayBehaviorLog]]) -> [DeterministicInsight] {
        let features = days.map { day in
            DayFeature(
                dayStart: day.dayStart,
                dayLabel: day.dayStart.formatted(.dateTime.month(.abbreviated).day()),
                totalSleepHours: day.totalSleepDuration / 3600,
                awakeMinutes: PatternMath.awakeMinutes(for: day),
                deepHours: PatternMath.durationHours(for: .deep, in: day),
                averageHRV: day.averageHRV,
                workoutMinutes: day.workoutMinutes ?? 0,
                eventLeadTimesByName: eventLeadTimes(for: day, logs: logsBySleepDay[day.dayStart] ?? [])
            )
        }

        var scoredInsights: [ScoredInsight] = []
        scoredInsights.append(contentsOf: buildEventTimingInsights(features: features))
        scoredInsights.append(contentsOf: buildHRVInsights(features: features))
        scoredInsights.append(contentsOf: buildWorkoutInsights(features: features))

        let ordered = scoredInsights
            .sorted { lhs, rhs in
                if lhs.rank == rhs.rank {
                    return lhs.insight.title < rhs.insight.title
                }
                return lhs.rank > rhs.rank
            }
            .map(\.insight)

        if ordered.isEmpty {
            return [
                DeterministicInsight(
                    id: "no-strong-signal",
                    title: "No strong repeatable pattern yet",
                    summary: "Selected nights do not show a stable directional relationship between events and sleep outcomes.",
                    confidence: .low,
                    evidence: []
                )
            ]
        }

        return Array(ordered.prefix(4))
    }

    private func buildEventTimingInsights(features: [DayFeature]) -> [ScoredInsight] {
        let allEventNames = Set(features.flatMap { Array($0.eventLeadTimesByName.keys) })
        var output: [ScoredInsight] = []

        for eventName in allEventNames {
            let withRecent = features.filter {
                ($0.eventLeadTimesByName[eventName] ?? []).contains(where: { (0 ... 360).contains($0) })
            }
            let withoutRecent = features.filter { feature in
                let leads = feature.eventLeadTimesByName[eventName] ?? []
                return leads.isEmpty || leads.allSatisfy { $0 > 360 || $0 < 0 }
            }

            guard !withRecent.isEmpty, !withoutRecent.isEmpty else { continue }

            let sleepDelta = average(withRecent.map(\.totalSleepHours)) - average(withoutRecent.map(\.totalSleepHours))
            if abs(sleepDelta) >= 0.35 {
                let direction = sleepDelta > 0 ? "higher" : "lower"
                let title = "\(eventName) timing vs total sleep"
                let summary = "When \(eventName.lowercased()) occurred within 6h before sleep, total sleep was \(direction) by \(formatHours(abs(sleepDelta)))."
                let confidence = confidenceLevel(effect: abs(sleepDelta), support: withRecent.count + withoutRecent.count)

                output.append(
                    ScoredInsight(
                        rank: abs(sleepDelta) + Double(withRecent.count + withoutRecent.count) * 0.12,
                        insight: DeterministicInsight(
                            id: "event-sleep-\(eventName.lowercased())",
                            title: title,
                            summary: summary,
                            confidence: confidence,
                            evidence: [
                                PatternEvidence(dayLabel: "Recent \(eventName)", metric: "Avg Sleep", value: formatHours(average(withRecent.map(\.totalSleepHours)))),
                                PatternEvidence(dayLabel: "No Recent \(eventName)", metric: "Avg Sleep", value: formatHours(average(withoutRecent.map(\.totalSleepHours))))
                            ]
                        )
                    )
                )
            }

            let awakeDelta = average(withRecent.map(\.awakeMinutes)) - average(withoutRecent.map(\.awakeMinutes))
            if abs(awakeDelta) >= 8 {
                let direction = awakeDelta > 0 ? "more" : "less"
                let title = "\(eventName) timing vs awake time"
                let summary = "\(eventName) within 6h of sleep aligned with \(direction) awake time by \(Int(abs(awakeDelta).rounded())) minutes."
                let confidence = confidenceLevel(effect: abs(awakeDelta) / 10, support: withRecent.count + withoutRecent.count)

                output.append(
                    ScoredInsight(
                        rank: abs(awakeDelta) / 10 + Double(withRecent.count + withoutRecent.count) * 0.12,
                        insight: DeterministicInsight(
                            id: "event-awake-\(eventName.lowercased())",
                            title: title,
                            summary: summary,
                            confidence: confidence,
                            evidence: [
                                PatternEvidence(dayLabel: "Recent \(eventName)", metric: "Avg Awake", value: "\(Int(average(withRecent.map(\.awakeMinutes)).rounded())) min"),
                                PatternEvidence(dayLabel: "No Recent \(eventName)", metric: "Avg Awake", value: "\(Int(average(withoutRecent.map(\.awakeMinutes)).rounded())) min")
                            ]
                        )
                    )
                )
            }
        }

        return output
    }

    private func buildHRVInsights(features: [DayFeature]) -> [ScoredInsight] {
        let withHRV = features.filter { $0.averageHRV != nil }
        guard withHRV.count >= 3 else { return [] }

        let sortedByHRV = withHRV.sorted { ($0.averageHRV ?? 0) < ($1.averageHRV ?? 0) }
        let split = max(sortedByHRV.count / 2, 1)

        let low = Array(sortedByHRV.prefix(split))
        let high = Array(sortedByHRV.suffix(split))
        guard !low.isEmpty, !high.isEmpty else { return [] }

        let sleepDelta = average(high.map(\.totalSleepHours)) - average(low.map(\.totalSleepHours))
        guard abs(sleepDelta) >= 0.25 else { return [] }

        let direction = sleepDelta > 0 ? "higher" : "lower"
        let summary = "Higher-HRV nights showed \(direction) total sleep by \(formatHours(abs(sleepDelta)))."

        return [
            ScoredInsight(
                rank: abs(sleepDelta) + Double(withHRV.count) * 0.15,
                insight: DeterministicInsight(
                    id: "hrv-sleep-link",
                    title: "HRV level vs sleep duration",
                    summary: summary,
                    confidence: confidenceLevel(effect: abs(sleepDelta), support: withHRV.count),
                    evidence: [
                        PatternEvidence(dayLabel: "Higher HRV", metric: "Avg Sleep", value: formatHours(average(high.map(\.totalSleepHours)))),
                        PatternEvidence(dayLabel: "Lower HRV", metric: "Avg Sleep", value: formatHours(average(low.map(\.totalSleepHours))))
                    ]
                )
            )
        ]
    }

    private func buildWorkoutInsights(features: [DayFeature]) -> [ScoredInsight] {
        let withWorkout = features.filter { $0.workoutMinutes >= 20 }
        let noWorkout = features.filter { $0.workoutMinutes < 5 }

        guard !withWorkout.isEmpty, !noWorkout.isEmpty else { return [] }

        let deepDelta = average(withWorkout.map(\.deepHours)) - average(noWorkout.map(\.deepHours))
        guard abs(deepDelta) >= 0.2 else { return [] }

        let direction = deepDelta > 0 ? "higher" : "lower"

        return [
            ScoredInsight(
                rank: abs(deepDelta) + Double(withWorkout.count + noWorkout.count) * 0.1,
                insight: DeterministicInsight(
                    id: "workout-deep-link",
                    title: "Workout minutes vs deep sleep",
                    summary: "Days with 20+ workout minutes had \(direction) deep sleep by \(formatHours(abs(deepDelta))).",
                    confidence: confidenceLevel(effect: abs(deepDelta), support: withWorkout.count + noWorkout.count),
                    evidence: [
                        PatternEvidence(dayLabel: "Workout 20+ min", metric: "Avg Deep", value: formatHours(average(withWorkout.map(\.deepHours)))),
                        PatternEvidence(dayLabel: "No Workout", metric: "Avg Deep", value: formatHours(average(noWorkout.map(\.deepHours))))
                    ]
                )
            )
        ]
    }

    private func eventLeadTimes(for day: DaySleepRecord, logs: [DayBehaviorLog]) -> [String: [Double]] {
        guard let sleepWindow = PatternMath.mainSleepWindow(for: day) else {
            return [:]
        }

        return Dictionary(grouping: logs, by: \.tagName)
            .mapValues { group in
                group.map { sleepWindow.start.timeIntervalSince($0.loggedAt) / 60 }
            }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func confidenceLevel(effect: Double, support: Int) -> InsightConfidence {
        if effect >= 0.8 && support >= 4 {
            return .high
        }
        if effect >= 0.35 && support >= 3 {
            return .medium
        }
        return .low
    }

    private func formatHours(_ value: Double) -> String {
        let roundedMinutes = Int((value * 60).rounded())
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    private struct DayFeature {
        let dayStart: Date
        let dayLabel: String
        let totalSleepHours: Double
        let awakeMinutes: Double
        let deepHours: Double
        let averageHRV: Double?
        let workoutMinutes: Double
        let eventLeadTimesByName: [String: [Double]]
    }

    private struct ScoredInsight {
        let rank: Double
        let insight: DeterministicInsight
    }
}

actor PatternAPIService {
    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidResponse
        case network(String)
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "AI service is not configured."
            case .invalidResponse:
                return "AI service returned an invalid response."
            case .network(let message):
                return message
            case .authenticationFailed:
                return "Could not authenticate with pattern service."
            }
        }
    }

    struct ChallengeResponse: Decodable {
        let installId: String
        let challengeToken: String
        let expiresAt: String
    }

    struct ExchangeResponse: Decodable {
        let accessToken: String
        let expiresAt: String
    }

    static func defaultBaseURL() -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PATTERN_API_BASE_URL") as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    private let baseURL: URL?
    private let urlSession: URLSession
    private let keyManager: DeviceKeyManager
    private var cachedToken: (value: String, expiry: Date)?

    init(baseURL: URL? = PatternAPIService.defaultBaseURL(), urlSession: URLSession = .shared, keyManager: DeviceKeyManager = DeviceKeyManager()) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.keyManager = keyManager
    }

    var isConfigured: Bool {
        baseURL != nil
    }

    func analyze(payload: PatternAnalysisPayload) async throws -> AIInsightResponse {
        guard baseURL != nil else {
            throw ServiceError.notConfigured
        }

        let token = try await validAccessToken(forceRefresh: false)

        do {
            return try await performAnalyze(payload: payload, accessToken: token)
        } catch ServiceError.authenticationFailed {
            let freshToken = try await validAccessToken(forceRefresh: true)
            return try await performAnalyze(payload: payload, accessToken: freshToken)
        }
    }

    private func performAnalyze(payload: PatternAnalysisPayload, accessToken: String) async throws -> AIInsightResponse {
        guard let endpoint = baseURL?.appendingPathComponent("v1/patterns/analyze") else {
            throw ServiceError.notConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        if http.statusCode == 401 {
            throw ServiceError.authenticationFailed
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.network("Pattern service error (\(http.statusCode)): \(body)")
        }

        do {
            return try JSONDecoder().decode(AIInsightResponse.self, from: data)
        } catch {
            throw ServiceError.invalidResponse
        }
    }

    private func validAccessToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh,
           let cachedToken,
           cachedToken.expiry.timeIntervalSinceNow > 30 {
            return cachedToken.value
        }

        guard let baseURL else {
            throw ServiceError.notConfigured
        }

        let installID = keyManager.installID()
        let publicKey = try keyManager.publicKeyBase64()

        let challengeRequest = ChallengeBody(installId: installID, publicKey: publicKey)
        let challengeResponse = try await postJSON(
            path: "v1/auth/challenge",
            baseURL: baseURL,
            body: challengeRequest,
            responseType: ChallengeResponse.self
        )

        let signature = try keyManager.signatureBase64(for: Data(challengeResponse.challengeToken.utf8))

        let exchangeRequest = ExchangeBody(
            installId: challengeResponse.installId,
            publicKey: publicKey,
            challengeToken: challengeResponse.challengeToken,
            signature: signature
        )

        let exchangeResponse = try await postJSON(
            path: "v1/auth/exchange",
            baseURL: baseURL,
            body: exchangeRequest,
            responseType: ExchangeResponse.self
        )

        guard let expiry = PatternFormatters.isoFormatter.date(from: exchangeResponse.expiresAt) else {
            throw ServiceError.invalidResponse
        }

        cachedToken = (value: exchangeResponse.accessToken, expiry: expiry)
        return exchangeResponse.accessToken
    }

    private func postJSON<Body: Encodable, Output: Decodable>(
        path: String,
        baseURL: URL,
        body: Body,
        responseType: Output.Type
    ) async throws -> Output {
        let endpoint = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.network("Auth request failed (\(http.statusCode)): \(bodyText)")
        }

        do {
            return try JSONDecoder().decode(Output.self, from: data)
        } catch {
            throw ServiceError.invalidResponse
        }
    }

    private struct ChallengeBody: Encodable {
        let installId: String
        let publicKey: String
    }

    private struct ExchangeBody: Encodable {
        let installId: String
        let publicKey: String
        let challengeToken: String
        let signature: String
    }
}

final class DeviceKeyManager {
    private let serviceName = "com.adithya.sleeplab.pattern"
    private let keyAccount = "ed25519-private-key"
    private let installIDKey = "pattern.install.id"

    func installID() -> String {
        if let stored = UserDefaults.standard.string(forKey: installIDKey), UUID(uuidString: stored) != nil {
            return stored
        }

        let newID = UUID().uuidString.lowercased()
        UserDefaults.standard.set(newID, forKey: installIDKey)
        return newID
    }

    func publicKeyBase64() throws -> String {
        let privateKey = try loadOrCreatePrivateKey()
        return privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    func signatureBase64(for message: Data) throws -> String {
        let privateKey = try loadOrCreatePrivateKey()
        let signature = try privateKey.signature(for: message)
        return signature.base64EncodedString()
    }

    private func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try loadPrivateKeyData(), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: existing) {
            return key
        }

        let created = Curve25519.Signing.PrivateKey()
        try savePrivateKeyData(created.rawRepresentation)
        return created
    }

    private func loadPrivateKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        return item as? Data
    }

    private func savePrivateKeyData(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: keyAccount
            ]

            let update: [String: Any] = [
                kSecValueData as String: data
            ]

            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return
        }

        throw KeychainError.unexpectedStatus(addStatus)
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            }
        }
    }
}
