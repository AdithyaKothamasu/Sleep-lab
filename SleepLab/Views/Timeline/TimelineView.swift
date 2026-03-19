import SwiftUI

private enum TimelineDisplayMode: String, CaseIterable, Identifiable {
    case sleepCards = "Sleep"
    case eventCards = "Events"

    var id: String { rawValue }
}

struct TimelineView: View {
    @EnvironmentObject private var viewModel: SleepLabViewModel
    @State private var showComparison = false
    @State private var showLogEvent = false
    @State private var displayMode: TimelineDisplayMode = .sleepCards
    @State private var eventsModeRefreshKey = UUID()

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        return value
    }

    private var eventColorHexByName: [String: String] {
        Dictionary(uniqueKeysWithValues: viewModel.events.map { ($0.name, $0.colorHex) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overviewPanel

                    if viewModel.sleepDays.isEmpty {
                        emptyState
                    } else {
                        if displayMode == .sleepCards {
                            ForEach(viewModel.sleepDays) { day in
                                NavigationLink {
                                    SleepDetailView(day: day)
                                } label: {
                                    SleepDayCardView(
                                        day: day,
                                        isSelected: viewModel.selectedDayIDs.contains(day.id),
                                        onToggleSelection: {
                                            viewModel.toggleSelection(for: day)
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    AppHaptics.impact(.light)
                                })
                            }
                        } else {
                            Group {
                                if !viewModel.isTodayCoveredBySleepDay {
                                    TodayEventCardView(
                                        logs: viewModel.todayLogs,
                                        workouts: viewModel.todayWorkouts,
                                        colorHexByEventName: eventColorHexByName
                                    )
                                }

                                ForEach(viewModel.sleepDays) { day in
                                    NavigationLink {
                                        SleepDetailView(day: day)
                                    } label: {
                                        DayEventCompactCardView(
                                            sleepDay: day,
                                            eventDayStart: viewModel.priorEventDay(forSleepDay: day.dayStart),
                                            logs: viewModel.logs(forSleepDay: day.dayStart),
                                            workouts: viewModel.workouts(forSleepDay: day.dayStart),
                                            colorHexByEventName: eventColorHexByName,
                                            isSelected: viewModel.selectedDayIDs.contains(day.id),
                                            onToggleSelection: { viewModel.toggleSelection(for: day) }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        AppHaptics.impact(.light)
                                    })
                                }
                            }
                            .id(eventsModeRefreshKey)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.clear)
            .navigationTitle("Sleep Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.refreshTimeline()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("Unselect All") {
                        viewModel.clearSelection()
                    }
                    .disabled(viewModel.selectedDayIDs.isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AgentSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Agent Settings")
                    .simultaneousGesture(TapGesture().onEnded {
                        AppHaptics.impact(.light)
                    })
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomFloatingBar
            }
            .navigationDestination(isPresented: $showComparison) {
                ComparisonView(days: viewModel.selectedDays, alignment: $viewModel.comparisonAlignment)
            }
            .sheet(isPresented: $showLogEvent) {
                LogBehaviorSheet(
                    events: viewModel.events,
                    initialDate: Date(),
                    showsDatePicker: true,
                    onCreateEventType: { name, colorHex in
                        viewModel.addCustomTag(name: name, colorHex: colorHex)
                    }
                ) { eventName, note, eventDateTime in
                    let dayStart = calendar.startOfDay(for: eventDateTime)
                    viewModel.addLog(for: dayStart, tagName: eventName, note: note, eventTime: eventDateTime)
                    eventsModeRefreshKey = UUID()
                }
            }
            .onChange(of: displayMode) {
                AppHaptics.selection()
            }
        }
    }

    private var bottomFloatingBar: some View {
        HStack(spacing: 12) {
            Button {
                AppHaptics.impact(.light)
                showLogEvent = true
            } label: {
                Label("Add Event", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FloatingActionButtonStyle(isPrimary: true, isEnabled: true))

            Button {
                AppHaptics.impact(.medium)
                showComparison = true
            } label: {
                Label("Compare \(viewModel.selectedDayIDs.count)", systemImage: "square.stack.3d.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FloatingActionButtonStyle(isPrimary: false, isEnabled: viewModel.canCompare))
            .disabled(!viewModel.canCompare)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [
                    SleepPalette.chartPlotBackground.opacity(0),
                    SleepPalette.chartPlotBackground.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var overviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select 2-5 days to compare")
                .font(.headline)
                .foregroundStyle(SleepPalette.titleText)

            Text("Each timeline uses a fixed hour scale, so longer sleep windows render wider instead of being compressed.")
                .font(.subheadline)
                .foregroundStyle(SleepPalette.mutedText)

            Picker("View Mode", selection: $displayMode) {
                ForEach(TimelineDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(SleepPalette.mutedText)

            Text("No sleep records imported yet.")
                .font(.headline)
                .foregroundStyle(SleepPalette.titleText)

            Text("Use Refresh to re-import from HealthKit.")
                .font(.subheadline)
                .foregroundStyle(SleepPalette.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FloatingActionButtonStyle: ButtonStyle {
    let isPrimary: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? Color.white : (isEnabled ? SleepPalette.titleText : SleepPalette.mutedText))
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundColor(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isPrimary ? 0.28 : 0.16), radius: isPrimary ? 18 : 12, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if isPrimary {
            return pressed ? SleepPalette.primary.opacity(0.82) : SleepPalette.primary
        }
        if !isEnabled {
            return SleepPalette.panelSecondary.opacity(0.55)
        }
        return pressed ? SleepPalette.panelSecondary.opacity(0.84) : SleepPalette.panelBackground
    }

    private var borderColor: Color {
        if isPrimary {
            return SleepPalette.primary.opacity(0.35)
        }
        return isEnabled ? SleepPalette.cardStroke : SleepPalette.cardStroke.opacity(0.45)
    }
}

private struct DayEventCompactCardView: View {
    let sleepDay: DaySleepRecord
    let eventDayStart: Date
    let logs: [DayBehaviorLog]
    let workouts: [WorkoutDetail]
    let colorHexByEventName: [String: String]
    let isSelected: Bool
    let onToggleSelection: () -> Void

    private var allEvents: [(name: String, color: Color, times: [Date])] {
        var grouped = Dictionary(grouping: logs, by: \.tagName)
            .map { name, items in
                (
                    name: name,
                    color: Color(hex: colorHexByEventName[name] ?? "#0A84FF"),
                    times: items.map(\.loggedAt).sorted()
                )
            }

        // Add workouts as event entries
        for workout in workouts {
            grouped.append((
                name: workout.activityType,
                color: Color(hex: "#30D158"),
                times: [workout.endDate]
            ))
        }

        return grouped.sorted {
            ($0.times.first ?? .distantPast) < ($1.times.first ?? .distantPast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sleepDay.dayStart.formatted(.dateTime.weekday(.abbreviated).month().day()))
                        .font(.headline)
                        .foregroundStyle(SleepPalette.titleText)

                    Text("Events from \(eventDayStart.formatted(.dateTime.month(.abbreviated).day()))")
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

            if allEvents.isEmpty {
                Text("No events recorded.")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(allEvents, id: \.name) { group in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(group.color)
                                .frame(width: 3, height: 18)

                            Text(group.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SleepPalette.titleText)

                            Spacer(minLength: 8)

                            Text(timesText(for: group.times))
                                .font(.caption2)
                                .foregroundStyle(SleepPalette.stageLabelText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(SleepPalette.chartPlotBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? SleepPalette.primary : SleepPalette.cardStroke, lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func timesText(for times: [Date]) -> String {
        guard !times.isEmpty else { return "--" }
        let formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        let visible = times.prefix(3).map { $0.formatted(formatter) }
        if times.count > 3 {
            return visible.joined(separator: "  ·  ") + "  +\(times.count - 3)"
        }
        return visible.joined(separator: "  ·  ")
    }
}

private struct TodayEventCardView: View {
    let logs: [DayBehaviorLog]
    let workouts: [WorkoutDetail]
    let colorHexByEventName: [String: String]

    private var allEvents: [(name: String, color: Color, times: [Date])] {
        var grouped = Dictionary(grouping: logs, by: \.tagName)
            .map { name, items in
                (
                    name: name,
                    color: Color(hex: colorHexByEventName[name] ?? "#0A84FF"),
                    times: items.map(\.loggedAt).sorted()
                )
            }

        for workout in workouts {
            grouped.append((
                name: workout.activityType,
                color: Color(hex: "#30D158"),
                times: [workout.endDate]
            ))
        }

        return grouped.sorted {
            ($0.times.first ?? .distantPast) < ($1.times.first ?? .distantPast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.headline)
                    .foregroundStyle(SleepPalette.titleText)

                Text(Date().formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
            }

            if allEvents.isEmpty {
                Text("No events recorded yet today.")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(allEvents, id: \.name) { group in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(group.color)
                                .frame(width: 3, height: 18)

                            Text(group.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SleepPalette.titleText)

                            Spacer(minLength: 8)

                            Text(timesText(for: group.times))
                                .font(.caption2)
                                .foregroundStyle(SleepPalette.stageLabelText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(SleepPalette.chartPlotBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func timesText(for times: [Date]) -> String {
        guard !times.isEmpty else { return "--" }
        let formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        let visible = times.prefix(3).map { $0.formatted(formatter) }
        if times.count > 3 {
            return visible.joined(separator: "  ·  ") + "  +\(times.count - 3)"
        }
        return visible.joined(separator: "  ·  ")
    }
}
