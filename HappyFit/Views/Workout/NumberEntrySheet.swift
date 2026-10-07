import SwiftUI

/// Tastierino numerico per inserire peso o ripetizioni.
struct NumberEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text: String

    let target: NumberTarget
    let onSave: (Double) -> Void

    init(target: NumberTarget, onSave: @escaping (Double) -> Void) {
        self.target = target
        self.onSave = onSave
        _text = State(initialValue: target.isWeight ? Formatting.weight(target.entry.weightKg) : "\(target.entry.reps)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(target.isWeight ? "Peso (kg)" : "Ripetizioni") {
                    TextField(target.isWeight ? "Peso" : "Ripetizioni", text: $text)
                        .keyboardType(target.isWeight ? .decimalPad : .numberPad)
                        .font(.largeTitle.monospacedDigit())
                        .focused($focused)
                }
            }
            .navigationTitle(target.isWeight ? "Peso" : "Ripetizioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", action: save).bold().disabled(Formatting.parseNumber(text) == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if let value = Formatting.parseNumber(text) { onSave(max(value, 0)) }
        dismiss()
    }
}
