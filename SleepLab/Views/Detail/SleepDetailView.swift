import SwiftUI

struct SleepDetailView: View {
    @EnvironmentObject private var viewModel: SleepLabViewModel

    let day: DaySleepRecord

    @State private var behaviorLogs: [DayBehaviorLog] = []
    @State private var pendingDeleteLog: DayBehaviorLog?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                chartCard
                behaviorCard
            }
            .padding(16)
        }
        .background(SleepPalette.backgroundGradient.ignoresSafeArea())
        .navigationTitle(day.dayStart.formatted(.dateTime.month().day().weekday()))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadLogs()
        }
        .alert(
            "Delete Event?",
            isPresented: Binding(
                get: { pendingDeleteLog != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteLog = nil
                    }
                }
            ),
            presenting: pendingDeleteLog
        ) { log in
            Button("Delete", role: .destructive) {
                viewModel.deleteLog(log)
                reloadLogs()
                pendingDeleteLog = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteLog = nil
            }
        } message: { log in
            Text("This deletes \(log.tagName) at \(log.loggedAt.formatted(.dateTime.hour().minute())).")
        }
    }

    private var eventDayStart: Date {
        viewModel.priorEventDay(forSleepDay: day.dayStart)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Night Summary")
                .font(.headline)
                .foregroundStyle(SleepPalette.titleText)

            metricRow(title: "Total Sleep", value: day.totalSleepDuration.hoursMinutes)
            metricRow(title: "Average Heart Rate", value: formatValue(day.averageHeartRate, suffix: "bpm"))
            metricRow(title: "Average HRV", value: formatValue(day.averageHRV, suffix: "ms"))
            metricRow(title: "Average Respiratory Rate", value: formatValue(day.averageRespiratoryRate, suffix: "br/min"))
            metricRow(title: "Workout Minutes", value: formatValue(day.workoutMinutes, suffix: "min"))
            metricRow(title: "Starter Sleep Score", value: "\(starterSleepScore()) / 100")
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detailed Hypnogram")
                .font(.headline)
                .foregroundStyle(SleepPalette.titleText)

            ScrollView(.horizontal, showsIndicators: false) {
                AppleSleepHypnogramView(
                    day: day,
                    alignment: .clockTime,
                    minimumWidth: max(day.chartWidth, 360),
                    chartHeight: 230,
                    showsStageLabels: true,
                    axisLabelMode: .clockTime
                )
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

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Events")
                    .font(.headline)
                    .foregroundStyle(SleepPalette.titleText)

                Text(eventDayStart.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SleepPalette.mutedText)

                Spacer()
            }

            if behaviorLogs.isEmpty {
                Text("No events for the previous day.")
                    .font(.subheadline)
                    .foregroundStyle(SleepPalette.mutedText)
            } else {
                ForEach(behaviorLogs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(log.tagName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SleepPalette.titleText)

                            Spacer()

                            Button(role: .destructive) {
                                pendingDeleteLog = log
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(SleepPalette.mutedText)
                        }

                        if let note = log.note {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(SleepPalette.mutedText)
                        }

                        Text(log.loggedAt.formatted(.dateTime.hour().minute()))
                            .font(.caption2)
                            .foregroundStyle(SleepPalette.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(SleepPalette.panelSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text("Add or edit events from the home timeline screen.")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
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

    private func reloadLogs() {
        behaviorLogs = viewModel.logs(forSleepDay: day.dayStart)
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(SleepPalette.mutedText)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SleepPalette.titleText)
        }
    }

    private func formatValue(_ value: Double?, suffix: String) -> String {
        guard let value else { return "-" }
        return "\(Int(value.rounded())) \(suffix)"
    }

    private func starterSleepScore() -> Int {
        let sleepHours = day.totalSleepDuration / 3600
        let sleepScore = min(max((sleepHours / 8.0) * 60.0, 0), 60)

        let hrvScore: Double
        if let hrv = day.averageHRV {
            hrvScore = min(max((hrv / 70.0) * 20.0, 0), 20)
        } else {
            hrvScore = 10
        }

        let hrScore: Double
        if let hr = day.averageHeartRate {
            hrScore = min(max((70 - hr) / 30.0 * 15.0, 0), 15)
        } else {
            hrScore = 8
        }

        let awakeMinutes = day.segments
            .filter { $0.stage == .awake }
            .reduce(0.0) { $0 + $1.duration / 60 }
        let continuityScore = max(0, 5 - (awakeMinutes / 20))

        return Int((sleepScore + hrvScore + hrScore + continuityScore).rounded())
    }
}

private extension TimeInterval {
    var hoursMinutes: String {
        let hours = Int(self / 3600)
        let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
}
