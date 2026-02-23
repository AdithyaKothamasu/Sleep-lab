import SwiftUI

struct LogBehaviorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let events: [BehaviorTag]
    let dayStart: Date
    let onSave: (String, String?, Date) -> Void

    @State private var selectedEvent: String = ""
    @State private var note: String = ""
    @State private var eventTime: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    Picker("Event type", selection: $selectedEvent) {
                        ForEach(events, id: \.name) { event in
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
                    DatePicker(
                        "Event time",
                        selection: $eventTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
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
                    selectedEvent = events.first?.name ?? ""
                }
                eventTime = defaultEventTime()
            }
        }
    }

    private func defaultEventTime() -> Date {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: dayStart)
        let nowComponents = calendar.dateComponents([.hour, .minute], from: Date())

        var combined = DateComponents()
        combined.year = dayComponents.year
        combined.month = dayComponents.month
        combined.day = dayComponents.day
        combined.hour = nowComponents.hour
        combined.minute = nowComponents.minute

        return calendar.date(from: combined) ?? Date()
    }
}
