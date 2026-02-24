import SwiftUI
import UIKit

struct LogBehaviorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let events: [BehaviorTag]
    let initialDate: Date
    let showsDatePicker: Bool
    let onSave: (String, String?, Date) -> Void

    @State private var selectedEvent: String = ""
    @State private var note: String = ""
    @State private var eventTime: Date = Date()

    private var selectableEvents: [BehaviorTag] {
        let preferredOrder = ["Workout", "Dinner", "Caffeine"]
        let filtered = events.filter { $0.name.caseInsensitiveCompare("Stress") != .orderedSame }

        return filtered.sorted { lhs, rhs in
            let leftIndex = preferredOrder.firstIndex(where: { $0.caseInsensitiveCompare(lhs.name) == .orderedSame }) ?? Int.max
            let rightIndex = preferredOrder.firstIndex(where: { $0.caseInsensitiveCompare(rhs.name) == .orderedSame }) ?? Int.max
            if leftIndex == rightIndex {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return leftIndex < rightIndex
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    Picker("Event type", selection: $selectedEvent) {
                        ForEach(selectableEvents, id: \.name) { event in
                            HStack {
                                Circle()
                                    .fill(Color(hex: event.colorHex))
                                    .frame(width: 10, height: 10)
                                Text(event.name)
                            }
                            .tag(event.name)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Time") {
                    if showsDatePicker {
                        DatePicker(
                            "Event date",
                            selection: $eventTime,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Event time")
                            .font(.subheadline)

                        MinuteIntervalTimePicker(
                            selectedDate: $eventTime,
                            minuteInterval: 5
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                    }
                }

                Section("Note (optional)") {
                    TextField("Any context for this event", text: $note, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle("Log Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedEvent, note, eventTime)
                        dismiss()
                    }
                    .disabled(selectedEvent.isEmpty)
                }
            }
            .onAppear {
                if selectedEvent.isEmpty {
                    selectedEvent = selectableEvents.first?.name ?? ""
                }
                eventTime = defaultEventTime()
            }
        }
    }

    private func defaultEventTime() -> Date {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: initialDate)
        let nowComponents = calendar.dateComponents([.hour, .minute], from: Date())

        var combined = DateComponents()
        combined.year = dayComponents.year
        combined.month = dayComponents.month
        combined.day = dayComponents.day
        combined.hour = nowComponents.hour
        combined.minute = roundedToFiveMinute(nowComponents.minute ?? 0)

        return calendar.date(from: combined) ?? Date()
    }

    private func roundedToFiveMinute(_ minute: Int) -> Int {
        let rounded = Int((Double(minute) / 5.0).rounded()) * 5
        return min(max(rounded, 0), 55)
    }
}

private struct MinuteIntervalTimePicker: UIViewRepresentable {
    @Binding var selectedDate: Date
    let minuteInterval: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDate: $selectedDate, minuteInterval: minuteInterval)
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = minuteInterval
        picker.locale = .current
        picker.addTarget(context.coordinator, action: #selector(Coordinator.onValueChanged(_:)), for: .valueChanged)
        picker.setDate(Self.roundedDate(selectedDate, step: minuteInterval), animated: false)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        uiView.minuteInterval = minuteInterval
        let rounded = Self.roundedDate(selectedDate, step: minuteInterval)
        if abs(uiView.date.timeIntervalSince(rounded)) > 0.5 {
            uiView.setDate(rounded, animated: false)
        }
    }

    private static func roundedDate(_ date: Date, step: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = components.minute ?? 0
        let roundedMinute = Int((Double(minute) / Double(step)).rounded()) * step
        components.minute = min(max(roundedMinute, 0), 55)
        return calendar.date(from: components) ?? date
    }

    final class Coordinator: NSObject {
        @Binding private var selectedDate: Date
        private let minuteInterval: Int

        init(selectedDate: Binding<Date>, minuteInterval: Int) {
            _selectedDate = selectedDate
            self.minuteInterval = minuteInterval
        }

        @objc func onValueChanged(_ sender: UIDatePicker) {
            let calendar = Calendar.current
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: sender.date)

            var combined = DateComponents()
            combined.year = dayComponents.year
            combined.month = dayComponents.month
            combined.day = dayComponents.day
            combined.hour = timeComponents.hour
            combined.minute = roundedMinute(timeComponents.minute ?? 0)

            if let merged = calendar.date(from: combined) {
                selectedDate = merged
            }
        }

        private func roundedMinute(_ minute: Int) -> Int {
            let rounded = Int((Double(minute) / Double(minuteInterval)).rounded()) * minuteInterval
            return min(max(rounded, 0), 55)
        }
    }
}
