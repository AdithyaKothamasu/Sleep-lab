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
    private let eventTrackInset: CGFloat = 10

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

    private var eventDomain: ClosedRange<Double> {
        0...24.75
    }

    private var eventMajorTicks: [Double] {
        [0, 3, 6, 9, 12, 15, 18, 21, 24]
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
                let hourWidth: CGFloat = 34
                let trackWidth = (CGFloat(eventDomain.upperBound - eventDomain.lowerBound) * hourWidth) + (eventTrackInset * 2)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Shown in clock time")
                            .font(.caption)
                            .foregroundStyle(SleepPalette.mutedText)

                        HStack(spacing: 10) {
                            Color.clear.frame(width: 56, height: 1)
                            rulerView(trackWidth: trackWidth, hourWidth: hourWidth)
                        }

                        ForEach(orderedDays) { day in
                            eventRow(for: day, trackWidth: trackWidth, hourWidth: hourWidth)
                        }
                    }
                    .frame(minWidth: trackWidth + 56, alignment: .leading)
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

    private func rulerView(trackWidth: CGFloat, hourWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(SleepPalette.chartGrid.opacity(0.5))
                .frame(width: trackWidth, height: 1)
                .offset(y: 1)

            ForEach(eventMajorTicks, id: \.self) { tick in
                let x = xPosition(for: tick, hourWidth: hourWidth)
                let labelX = min(max(x, 14), trackWidth - 14)

                Rectangle()
                    .fill(SleepPalette.chartGrid.opacity(0.55))
                    .frame(width: 1, height: 6)
                    .offset(x: x, y: 0)

                Text(clockAxisLabel(for: tick))
                    .font(.caption2)
                    .foregroundStyle(SleepPalette.stageLabelText)
                    .frame(width: 28)
                    .offset(x: labelX - 14, y: 8)
            }
        }
        .frame(width: trackWidth, height: 24, alignment: .leading)
    }

    private func eventRow(for day: DaySleepRecord, trackWidth: CGFloat, hourWidth: CGFloat) -> some View {
        let dayLabel = day.dayStart.formatted(.dateTime.month(.abbreviated).day())
        let points = filteredEventPoints.filter { $0.dayLabel == dayLabel }

        return HStack(spacing: 10) {
            Text(dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SleepPalette.stageLabelText)
                .frame(width: 56, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SleepPalette.chartPlotBackground)

                ForEach(eventMajorTicks, id: \.self) { tick in
                    Rectangle()
                        .fill(SleepPalette.chartGrid.opacity(0.4))
                        .frame(width: 1, height: 36)
                        .offset(x: xPosition(for: tick, hourWidth: hourWidth), y: 2)
                }

                if let sleepBand = sleepBand(for: day, hourWidth: hourWidth) {
                    Rectangle()
                        .fill(SleepPalette.primary.opacity(0.15))
                        .frame(width: sleepBand.width, height: 12)
                        .offset(x: sleepBand.x, y: 14)
                }

                ForEach(points) { point in
                    eventMarker(for: point, hourWidth: hourWidth)
                }
            }
            .frame(width: trackWidth, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func eventMarker(for point: EventTimelinePoint, hourWidth: CGFloat) -> some View {
        let color = eventColor(for: point.eventName)
        let x = xPosition(for: point.hour, hourWidth: hourWidth)

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(color.opacity(0.35))
                .frame(width: 2, height: 20)
                .offset(y: 8)

            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                )
        }
        .offset(x: x - 5, y: 0)
    }

    private func xPosition(for hour: Double, hourWidth: CGFloat) -> CGFloat {
        let bounded = min(max(hour, eventDomain.lowerBound), eventDomain.upperBound)
        return (CGFloat(bounded - eventDomain.lowerBound) * hourWidth) + eventTrackInset
    }

    private func sleepBand(for day: DaySleepRecord, hourWidth: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        guard let ranges = day.hypnogramRanges(alignment: .clockTime).sorted(by: { $0.startHour < $1.startHour }).first,
              let end = day.hypnogramRanges(alignment: .clockTime).map(\.endHour).max() else {
            return nil
        }
        let startX = xPosition(for: ranges.startHour, hourWidth: hourWidth)
        let endX = xPosition(for: end, hourWidth: hourWidth)
        return (x: startX, width: max(endX - startX, 6))
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

    private func clockAxisLabel(for hour: Double) -> String {
        let normalized = (Int(hour.rounded()) % 24 + 24) % 24
        let suffix = normalized < 12 ? "AM" : "PM"
        let hour12 = normalized % 12 == 0 ? 12 : normalized % 12
        return "\(hour12) \(suffix)"
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
