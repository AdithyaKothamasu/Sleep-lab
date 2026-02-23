import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var viewModel: SleepLabViewModel
    @State private var showComparison = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overviewPanel

                    if viewModel.sleepDays.isEmpty {
                        emptyState
                    } else {
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
