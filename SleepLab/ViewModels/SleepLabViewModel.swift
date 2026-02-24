import Foundation

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

    private let healthKitService: HealthKitService
    private let behaviorRepository: BehaviorRepository
    private var calendar = Calendar(identifier: .gregorian)

    init(healthKitService: HealthKitService, behaviorRepository: BehaviorRepository) {
        self.healthKitService = healthKitService
        self.behaviorRepository = behaviorRepository
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

    func requestAccessAndLoadTimeline() {
        guard loadState != .loading && loadState != .requestingAuthorization else { return }

        loadState = .requestingAuthorization
        errorMessage = nil

        Task {
            do {
                try await healthKitService.requestAuthorization()
                loadState = .loading

                let days = try await healthKitService.loadSleepDays(forLast: 30)

                sleepDays = days
                if selectedDayIDs.count > 5 {
                    selectedDayIDs = Set(selectedDayIDs.prefix(5))
                }
                loadState = .ready
            } catch let error as HealthKitServiceError {
                switch error {
                case .authorizationDenied:
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
        } catch {
            errorMessage = "Could not save event."
        }
    }

    func deleteLog(_ log: DayBehaviorLog) {
        do {
            try behaviorRepository.deleteLog(id: log.id)
        } catch {
            errorMessage = "Could not delete event."
        }
    }

    func priorEventDay(forSleepDay dayStart: Date) -> Date {
        let normalized = calendar.startOfDay(for: dayStart)
        return calendar.date(byAdding: .day, value: -1, to: normalized) ?? normalized
    }
}
