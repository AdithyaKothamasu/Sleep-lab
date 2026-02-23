import SwiftUI

struct AddTagSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = "#2563EB"

    let onSave: (String, String) -> Void

    private let colorOptions = [
        "#2563EB",
        "#0EA5A4",
        "#D97706",
        "#DC2626",
        "#7C3AED",
        "#DB2777"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Event name") {
                    TextField("Example: Late Snack", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(colorOptions, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if colorHex == hex {
                                            Circle().stroke(SleepPalette.primary, lineWidth: 3)
                                        }
                                    }
                                    .onTapGesture {
                                        colorHex = hex
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Event Type")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, colorHex)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
