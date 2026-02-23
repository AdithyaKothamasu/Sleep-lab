import Charts
import SwiftUI

struct SleepDayCardView: View {
    let day: DaySleepRecord
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metrics

            ScrollView(.horizontal, showsIndicators: false) {
                chart
                    .frame(height: 184)
            }
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? SleepPalette.primary : SleepPalette.cardStroke, lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.dayStart.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.headline)
                    .foregroundStyle(SleepPalette.titleText)

                Text("Tap card for details")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
            }

            Spacer()

            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? SleepPalette.primary : SleepPalette.mutedText)
            }
            .buttonStyle(.plain)
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metricBadge(title: "Sleep", value: day.totalSleepDuration.hoursMinutes)
            metricBadge(title: "HR", value: formatted(day.averageHeartRate, suffix: "bpm"))
            metricBadge(title: "HRV", value: formatted(day.averageHRV, suffix: "ms"))
            metricBadge(title: "Workout", value: formatted(day.workoutMinutes, suffix: "min"))
        }
    }

    private var chart: some View {
        AppleSleepHypnogramView(
            day: day,
            alignment: .clockTime,
            minimumWidth: day.chartWidth,
            chartHeight: 184,
            showsStageLabels: false,
            axisLabelMode: .offsetHours
        )
    }

    private func metricBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(SleepPalette.mutedText)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SleepPalette.titleText)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(SleepPalette.metricChipBackground)
        .clipShape(Capsule())
    }

    private func formatted(_ value: Double?, suffix: String) -> String {
        guard let value else { return "-" }

        if suffix == "min" {
            return "\(Int(value.rounded())) \(suffix)"
        }

        return "\(Int(value.rounded())) \(suffix)"
    }
}

enum HypnogramAxisLabelMode {
    case clockTime
    case offsetHours
}

struct AppleSleepHypnogramView: View {
    let day: DaySleepRecord
    let alignment: ComparisonAlignment
    let minimumWidth: Double
    let chartHeight: CGFloat
    let showsStageLabels: Bool
    let axisLabelMode: HypnogramAxisLabelMode

    private var ranges: [HypnogramRange] {
        day.hypnogramRanges(alignment: alignment)
    }

    private var transitions: [HypnogramTransition] {
        day.hypnogramTransitions(alignment: alignment)
    }

    private var maxHour: Double {
        max(day.hypnogramMaxHour(alignment: alignment), 4)
    }

    private var chartWidth: CGFloat {
        max(CGFloat(minimumWidth), CGFloat(maxHour) * 58)
    }

    private var baselineDate: Date {
        switch alignment {
        case .clockTime:
            return day.dayStart
        case .sleepStart:
            return day.firstSegmentStart ?? day.dayStart
        }
    }

    var body: some View {
        Group { ranges.isEmpty ? AnyView(emptyState) : AnyView(chartBody) }
        .frame(width: chartWidth, height: chartHeight)
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(SleepPalette.chartPlotBackground)
            .overlay {
                Text("No sleep stage data")
                    .font(.subheadline)
                    .foregroundStyle(SleepPalette.mutedText)
            }
    }

    private var chartBody: some View {
        Chart {
            transitionMarks
            rangeMarks
        }
        .chartXScale(domain: 0...maxHour)
        .chartYScale(domain: -0.5...3.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: SleepStage.appleAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(SleepPalette.chartGrid.opacity(0.7))

                if showsStageLabels,
                   let row = value.as(Double.self),
                   let stage = SleepStage.stage(forAppleRow: row) {
                    AxisValueLabel {
                        Text(stage.displayName)
                            .font(.caption)
                            .foregroundStyle(SleepPalette.stageLabelText)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom, values: .stride(by: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(SleepPalette.chartGrid.opacity(0.5))
                AxisValueLabel {
                    if let hour = value.as(Double.self) {
                        Text(axisLabel(for: hour))
                            .font(.caption)
                            .foregroundStyle(SleepPalette.stageLabelText)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(SleepPalette.chartPlotBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .chartLegend(.hidden)
    }

    @ChartContentBuilder
    private var transitionMarks: some ChartContent {
        ForEach(transitions) { transition in
            RuleMark(
                x: .value("Transition", transition.hour),
                yStart: .value("Start Row", transition.startRow - 0.24),
                yEnd: .value("End Row", transition.endRow + 0.24)
            )
            .foregroundStyle(SleepPalette.stageColor(for: transition.toStage).opacity(0.2))
            .lineStyle(.init(lineWidth: 3, lineCap: .round))
        }
    }

    @ChartContentBuilder
    private var rangeMarks: some ChartContent {
        ForEach(ranges) { range in
            BarMark(
                xStart: .value("Start Hour", range.startHour),
                xEnd: .value("End Hour", range.endHour),
                y: .value("Stage", range.stage.appleRow),
                height: .fixed(22)
            )
            .foregroundStyle(SleepPalette.stageColor(for: range.stage))
            .cornerRadius(8)
        }
    }

    private func axisLabel(for hour: Double) -> String {
        switch axisLabelMode {
        case .offsetHours:
            return "\(Int(hour))h"
        case .clockTime:
            let targetDate = baselineDate.addingTimeInterval(hour * 3600)
            return Self.timeFormatter.string(from: targetDate)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("ha")
        return formatter
    }()
}

private extension TimeInterval {
    var hoursMinutes: String {
        let hours = Int(self / 3600)
        let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
}
