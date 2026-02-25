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
    @State private var showAddEventType = false
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
                            }
                        } else {
                            Group {
                                if !viewModel.isTodayCoveredBySleepDay {
                                    TodayEventCardView(
                                        logs: viewModel.todayLogs,
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
                                            colorHexByEventName: eventColorHexByName,
                                            isSelected: viewModel.selectedDayIDs.contains(day.id),
                                            onToggleSelection: { viewModel.toggleSelection(for: day) }
                                        )
                                    }
                                    .buttonStyle(.plain)
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
                    Menu {
                        Button {
                            showLogEvent = true
                        } label: {
                            Label("Log Event", systemImage: "plus.circle")
                        }
                        .disabled(viewModel.events.isEmpty)

                        Button {
                            showAddEventType = true
                        } label: {
                            Label("New Event Type", systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add Event")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showComparison = true
                    } label: {
                        Label("Compare (\(viewModel.selectedDayIDs.count))", systemImage: "square.stack.3d.up")
                    }
                    .disabled(!viewModel.canCompare)
                }
            }
            .navigationDestination(isPresented: $showComparison) {
                ComparisonView(days: viewModel.selectedDays, alignment: $viewModel.comparisonAlignment)
            }
            .sheet(isPresented: $showAddEventType) {
                AddTagSheet { name, colorHex in
                    viewModel.addCustomTag(name: name, colorHex: colorHex)
                }
            }
            .sheet(isPresented: $showLogEvent) {
                LogBehaviorSheet(
                    events: viewModel.events,
                    initialDate: Date(),
                    showsDatePicker: true
                ) { eventName, note, eventDateTime in
                    let dayStart = calendar.startOfDay(for: eventDateTime)
                    viewModel.addLog(for: dayStart, tagName: eventName, note: note, eventTime: eventDateTime)
                    eventsModeRefreshKey = UUID()
                }
            }
        }
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

private struct DayEventCompactCardView: View {
    let sleepDay: DaySleepRecord
    let eventDayStart: Date
    let logs: [DayBehaviorLog]
    let colorHexByEventName: [String: String]
    let isSelected: Bool
    let onToggleSelection: () -> Void

    private var groupedEvents: [(name: String, color: Color, times: [Date])] {
        Dictionary(grouping: logs, by: \.tagName)
            .map { name, items in
                (
                    name: name,
                    color: Color(hex: colorHexByEventName[name] ?? "#0A84FF"),
                    times: items.map(\.loggedAt).sorted()
                )
            }
            .sorted {
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

            if groupedEvents.isEmpty {
                Text("No events recorded.")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groupedEvents, id: \.name) { group in
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
    let colorHexByEventName: [String: String]

    private var groupedEvents: [(name: String, color: Color, times: [Date])] {
        Dictionary(grouping: logs, by: \.tagName)
            .map { name, items in
                (
                    name: name,
                    color: Color(hex: colorHexByEventName[name] ?? "#0A84FF"),
                    times: items.map(\.loggedAt).sorted()
                )
            }
            .sorted {
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

            if groupedEvents.isEmpty {
                Text("No events recorded yet today.")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groupedEvents, id: \.name) { group in
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
