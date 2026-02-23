import Charts
import SwiftUI

struct ComparisonView: View {
    struct StageTimelineSegment: Identifiable {
        let id = UUID()
        let dayLabel: String
        let startHour: Double
        let endHour: Double
        let stage: SleepStage
    }

    struct EventTimelinePoint: Identifiable {
        let id = UUID()
        let dayLabel: String
        let hour: Double
        let eventName: String
    }

    @EnvironmentObject private var viewModel: SleepLabViewModel

    let days: [DaySleepRecord]
    @Binding var alignment: ComparisonAlignment

    @State private var visibleStages: Set<SleepStage> = Set(SleepStage.comparisonStages)
    @State private var visibleEventNames: Set<String> = []

    private var orderedDays: [DaySleepRecord] {
        days.sorted { $0.dayStart > $1.dayStart }
    }

    private var allStages: [SleepStage] {
        SleepStage.comparisonStages
    }

    private var selectedStagesInOrder: [SleepStage] {
        allStages.filter { visibleStages.contains($0) }
    }

    private var stageSegments: [StageTimelineSegment] {
        orderedDays.flatMap { day in
            day.hypnogramRanges(alignment: alignment)
                .filter { visibleStages.contains($0.stage) }
                .map {
                    StageTimelineSegment(
                        dayLabel: day.dayStart.formatted(.dateTime.month(.abbreviated).day()),
                        startHour: $0.startHour,
                        endHour: $0.endHour,
                        stage: $0.stage
                    )
                }
        }
    }

    private var sleepMaxHour: Double {
        max(orderedDays.map { $0.hypnogramMaxHour(alignment: alignment) }.max() ?? 0, 4)
    }

    private var allEventPoints: [EventTimelinePoint] {
        orderedDays.flatMap { day in
            let logs = viewModel.logs(for: day.dayStart)
            return logs.map { log in
                EventTimelinePoint(
                    dayLabel: day.dayStart.formatted(.dateTime.month(.abbreviated).day()),
                    hour: eventHour(for: log, on: day),
                    eventName: log.tagName
                )
            }
        }
    }

    private var eventNames: [String] {
        Array(Set(allEventPoints.map(\.eventName))).sorted()
    }

    private var filteredEventPoints: [EventTimelinePoint] {
        allEventPoints.filter { visibleEventNames.contains($0.eventName) }
    }

    private var stageDomain: ClosedRange<Double> {
        0...(sleepMaxHour + 0.8)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Comparison")
                    .font(.largeTitle.bold())
                    .foregroundStyle(SleepPalette.titleText)

                Picker("Alignment", selection: $alignment) {
                    ForEach(ComparisonAlignment.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                stageFilterChips
                stageTimelineCard
                eventFilterChips
                eventsTimelineCard
                durationNumbersCard
            }
            .padding(16)
        }
        .background(SleepPalette.backgroundGradient.ignoresSafeArea())
        .onAppear {
            initializeEventFilters()
        }
        .onChange(of: eventNames) {
            initializeEventFilters()
        }
    }

    private var stageFilterChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible Sleep Stages")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SleepPalette.mutedText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(allStages) { stage in
                        Button {
                            toggleStage(stage)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(SleepPalette.stageColor(for: stage))
                                    .frame(width: 9, height: 9)
                                Text(stage.displayName)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(visibleStages.contains(stage) ? SleepPalette.panelSecondary : SleepPalette.panelBackground)
                            .overlay(
                                Capsule()
                                    .stroke(visibleStages.contains(stage) ? SleepPalette.primary : SleepPalette.cardStroke, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var stageTimelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stage-by-Stage Sleep Comparison")
                .font(.headline)
                .foregroundStyle(SleepPalette.titleText)

            if visibleStages.isEmpty {
                placeholderText("Select at least one sleep stage.")
            } else if stageSegments.isEmpty {
                placeholderText("No sleep-stage data for selected stages.")
            } else {
                Chart(stageSegments) { segment in
                    BarMark(
                        xStart: .value("Start", segment.startHour),
                        xEnd: .value("End", segment.endHour),
                        y: .value("Day", segment.dayLabel),
                        height: .fixed(24)
                    )
                    .foregroundStyle(SleepPalette.stageColor(for: segment.stage))
                }
                .frame(height: CGFloat(max(orderedDays.count, 2)) * 44)
                .chartXScale(domain: stageDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(SleepPalette.chartGrid.opacity(0.4))
                        AxisValueLabel().foregroundStyle(SleepPalette.stageLabelText)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .stride(by: 2)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(SleepPalette.chartGrid.opacity(0.45))
                        AxisValueLabel {
                            if let hour = value.as(Double.self) {
                                Text(axisLabel(for: hour, alignment: alignment))
                                    .foregroundStyle(SleepPalette.stageLabelText)
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(.bottom, 8)
                        .background(SleepPalette.chartPlotBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var eventFilterChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible Events")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SleepPalette.mutedText)

            if eventNames.isEmpty {
                Text("No events logged for selected days.")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(eventNames, id: \.self) { eventName in
                            Button {
                                toggleEvent(eventName)
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(eventColor(for: eventName))
                                        .frame(width: 9, height: 9)
                                    Text(eventName)
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(visibleEventNames.contains(eventName) ? SleepPalette.panelSecondary : SleepPalette.panelBackground)
                                .overlay(
                                    Capsule()
                                        .stroke(visibleEventNames.contains(eventName) ? SleepPalette.primary : SleepPalette.cardStroke, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var eventsTimelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Timing Comparison")
                .font(.headline)
                .foregroundStyle(SleepPalette.titleText)

            if eventNames.isEmpty {
                placeholderText("Log events on day detail screens to compare timing impact.")
            } else if visibleEventNames.isEmpty {
                placeholderText("Select at least one event type.")
            } else if filteredEventPoints.isEmpty {
                placeholderText("No matching events for the selected filters.")
            } else {
                Text("Clock-time view. Each day shows selected events closest to that night's main sleep window.")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(orderedDays) { day in
                        let timings = dayEventTimings(for: day)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(day.dayStart.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SleepPalette.titleText)

                                Spacer()

                                Text("Sleep \(mainSleepWindowText(for: day))")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(SleepPalette.primary)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(SleepPalette.primary.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            if timings.isEmpty {
                                Text("No selected events logged for this day.")
                                    .font(.caption)
                                    .foregroundStyle(SleepPalette.mutedText)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(timings, id: \.eventName) { timing in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(eventColor(for: timing.eventName))
                                                .frame(width: 8, height: 8)

                                            Text(timing.eventName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(SleepPalette.stageLabelText)

                                            Spacer()

                                            Text(formattedClockTime(for: timing.hour, on: day.dayStart))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(SleepPalette.titleText)

                                            if timing.extraCount > 0 {
                                                Text("+\(timing.extraCount)")
                                                    .font(.caption2)
                                                    .foregroundStyle(SleepPalette.mutedText)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(SleepPalette.panelSecondary)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(SleepPalette.chartPlotBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var durationNumbersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stage Duration Numbers")
                .font(.headline)
                .foregroundStyle(SleepPalette.titleText)

            if selectedStagesInOrder.isEmpty {
                placeholderText("Select at least one sleep stage.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            headerCell("Stage", width: 90, alignment: .leading)
                            ForEach(orderedDays) { day in
                                headerCell(day.dayStart.formatted(.dateTime.month(.abbreviated).day()), width: 70, alignment: .trailing)
                            }
                            headerCell("Avg", width: 70, alignment: .trailing)
                        }

                        ForEach(selectedStagesInOrder) { stage in
                            HStack(spacing: 12) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(SleepPalette.stageColor(for: stage))
                                        .frame(width: 8, height: 8)
                                    Text(stage.displayName)
                                        .foregroundStyle(SleepPalette.titleText)
                                }
                                .font(.caption.weight(.semibold))
                                .frame(width: 90, alignment: .leading)

                                ForEach(orderedDays) { day in
                                    Text(durationText(for: stage, in: day))
                                        .font(.caption)
                                        .foregroundStyle(SleepPalette.stageLabelText)
                                        .frame(width: 70, alignment: .trailing)
                                }

                                Text(averageDurationText(for: stage))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SleepPalette.titleText)
                                    .frame(width: 70, alignment: .trailing)
                            }
                        }
                    }
                    .padding(12)
                    .background(SleepPalette.panelSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func dayEventTimings(for day: DaySleepRecord) -> [(eventName: String, hour: Double, extraCount: Int)] {
        let dayLogs = viewModel.logs(for: day.dayStart)
        let sleepStart = mainSleepWindow(for: day)?.start

        var entries: [(eventName: String, hour: Double, extraCount: Int)] = []

        for eventName in eventNames where visibleEventNames.contains(eventName) {
            let logs = dayLogs.filter { $0.tagName == eventName }
            guard !logs.isEmpty else { continue }

            let hours = logs.map { eventHour(for: $0, on: day) }
            let selectedHour: Double

            if let sleepStart {
                selectedHour = hours.min {
                    clockDistance($0, to: sleepStart) < clockDistance($1, to: sleepStart)
                } ?? hours[0]
            } else {
                selectedHour = hours.min() ?? hours[0]
            }

            entries.append(
                (
                    eventName: eventName,
                    hour: selectedHour,
                    extraCount: max(logs.count - 1, 0)
                )
            )
        }

        if let sleepStart {
            return entries.sorted { clockDistance($0.hour, to: sleepStart) < clockDistance($1.hour, to: sleepStart) }
        }

        return entries.sorted { $0.hour < $1.hour }
    }

    private func mainSleepWindow(for day: DaySleepRecord) -> (start: Double, end: Double)? {
        let ordered = day.segments.sorted { $0.startDate < $1.startDate }
        guard !ordered.isEmpty else { return nil }

        struct Window {
            var start: Date
            var end: Date
            var duration: TimeInterval
        }

        var windows: [Window] = []
        var current = Window(
            start: ordered[0].startDate,
            end: ordered[0].endDate,
            duration: ordered[0].duration
        )

        for segment in ordered.dropFirst() {
            let gap = segment.startDate.timeIntervalSince(current.end)
            if gap <= 45 * 60 {
                current.end = max(current.end, segment.endDate)
                current.duration += segment.duration
            } else {
                windows.append(current)
                current = Window(
                    start: segment.startDate,
                    end: segment.endDate,
                    duration: segment.duration
                )
            }
        }

        windows.append(current)

        guard let mainWindow = windows.max(by: { $0.duration < $1.duration }) else {
            return nil
        }

        let startHour = max(mainWindow.start.timeIntervalSince(day.dayStart) / 3600, 0)
        let endHour = max(mainWindow.end.timeIntervalSince(day.dayStart) / 3600, 0)
        return (start: startHour, end: endHour)
    }

    private func mainSleepWindowText(for day: DaySleepRecord) -> String {
        guard let window = mainSleepWindow(for: day) else { return "--" }
        let start = formattedClockTime(for: window.start, on: day.dayStart)
        let end = formattedClockTime(for: window.end, on: day.dayStart)
        return "\(start)-\(end)"
    }

    private func clockDistance(_ first: Double, to second: Double) -> Double {
        let raw = abs(first - second).truncatingRemainder(dividingBy: 24)
        return min(raw, 24 - raw)
    }

    private func formattedClockTime(for hour: Double, on dayStart: Date) -> String {
        let normalized = hour.truncatingRemainder(dividingBy: 24)
        let safeHour = normalized < 0 ? normalized + 24 : normalized
        let date = dayStart.addingTimeInterval(safeHour * 3600)
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(SleepPalette.mutedText)
            .frame(width: width, alignment: alignment)
    }

    private func durationHours(for stage: SleepStage, in day: DaySleepRecord) -> Double {
        let seconds = day.segments.reduce(0.0) { partial, segment in
            let normalized = segment.stage.normalizedForHypnogram
            guard normalized == stage else { return partial }
            return partial + segment.duration
        }
        return seconds / 3600
    }

    private func durationText(for stage: SleepStage, in day: DaySleepRecord) -> String {
        formatHours(durationHours(for: stage, in: day))
    }

    private func averageDurationText(for stage: SleepStage) -> String {
        guard !orderedDays.isEmpty else { return "-" }
        let average = orderedDays.map { durationHours(for: stage, in: $0) }.reduce(0, +) / Double(orderedDays.count)
        return formatHours(average)
    }

    private func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)h \(m)m"
    }

    private func placeholderText(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(SleepPalette.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }

    private func toggleStage(_ stage: SleepStage) {
        if visibleStages.contains(stage) {
            visibleStages.remove(stage)
        } else {
            visibleStages.insert(stage)
        }
    }

    private func toggleEvent(_ eventName: String) {
        if visibleEventNames.contains(eventName) {
            visibleEventNames.remove(eventName)
        } else {
            visibleEventNames.insert(eventName)
        }
    }

    private func initializeEventFilters() {
        let names = Set(eventNames)
        if visibleEventNames.isEmpty {
            visibleEventNames = names
            return
        }

        visibleEventNames.formIntersection(names)
        if visibleEventNames.isEmpty {
            visibleEventNames = names
        }
    }

    private func eventHour(for log: DayBehaviorLog, on day: DaySleepRecord) -> Double {
        log.loggedAt.timeIntervalSince(day.dayStart) / 3600
    }

    private func eventColor(for eventName: String) -> Color {
        guard let event = viewModel.events.first(where: { $0.name == eventName }) else {
            return SleepPalette.primary
        }
        return Color(hex: event.colorHex)
    }

    private func axisLabel(for hour: Double, alignment: ComparisonAlignment) -> String {
        switch alignment {
        case .sleepStart:
            let rounded = Int(hour.rounded())
            if rounded == 0 {
                return "0h"
            }
            return rounded > 0 ? "+\(rounded)h" : "\(rounded)h"
        case .clockTime:
            let normalized = (Int(hour.rounded()) % 24 + 24) % 24
            let suffix = normalized < 12 ? "a" : "p"
            let hour12 = normalized % 12 == 0 ? 12 : normalized % 12
            return "\(hour12)\(suffix)"
        }
    }
}
