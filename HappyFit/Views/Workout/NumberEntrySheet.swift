import SwiftUI

/// Tastierino per inserire peso o ripetizioni: tasti grandi, pensato per l'uso a una mano.
/// Stesso flusso di prima (Annulla / Fine in alto); la prima cifra digitata sostituisce il valore attuale.
struct NumberEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 56
    @State private var text: String
    @State private var replacesOnInput = true
    @State private var presses = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let target: NumberTarget
    let onSave: (Double) -> Void

    init(target: NumberTarget, onSave: @escaping (Double) -> Void) {
        self.target = target
        self.onSave = onSave
        _text = State(initialValue: target.isWeight ? Formatting.weight(target.entry.weightKg) : "\(target.entry.reps)")
    }

    private var isValid: Bool { Formatting.parseNumber(text) != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                VStack(spacing: Spacing.xs) {
                    Eyebrow(target.isWeight ? "Peso (kg)" : "Ripetizioni")
                        .foregroundStyle(palette.textSecondary)
                    Text(text.isEmpty ? "0" : text)
                        .font(.system(size: displaySize, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(replacesOnInput ? palette.textSecondary : palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityLabel(target.isWeight ? "Peso \(text) chilogrammi" : "Ripetizioni \(text)")
                }
                .frame(maxWidth: .infinity)
                .hfCard(padding: Spacing.l)

                Keypad(allowsDecimal: target.isWeight, onKey: press)
                    // Vibrazione leggera a ogni tasto (spenta con "Riduci movimento").
                    .sensoryFeedback(trigger: presses) { _, _ in reduceMotion ? nil : .selection }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .background(palette.background)
            .navigationTitle(target.isWeight ? "Peso" : "Ripetizioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", action: save).bold().disabled(!isValid)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func press(_ key: Keypad.Key) {
        presses += 1
        switch key {
        case .digit(let digit):
            if replacesOnInput { text = "" }
            replacesOnInput = false
            guard text.count < 6 else { return }
            text = (text == "0" ? "" : text) + String(digit)
        case .decimal:
            if replacesOnInput { text = "0" }
            replacesOnInput = false
            guard !text.contains(","), text.count < 5 else { return }
            text += text.isEmpty ? "0," : ","
        case .delete:
            replacesOnInput = false
            if !text.isEmpty { text.removeLast() }
        }
    }

    private func save() {
        if let value = Formatting.parseNumber(text) { onSave(max(value, 0)) }
        dismiss()
    }
}

/// Griglia 3 × 4 di tasti grandi (almeno 64 pt di altezza).
private struct Keypad: View {
    enum Key { case digit(Int), decimal, delete }

    @Environment(\.palette) private var palette
    let allowsDecimal: Bool
    let onKey: (Key) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            ForEach(1...9, id: \.self) { digit in
                key(Text("\(digit)"), label: "\(digit)") { onKey(.digit(digit)) }
            }
            if allowsDecimal {
                key(Text(","), label: "virgola") { onKey(.decimal) }
            } else {
                Color.clear.frame(minHeight: 64).accessibilityHidden(true)
            }
            key(Text("0"), label: "0") { onKey(.digit(0)) }
            key(Image(systemName: "delete.left"), label: "Cancella") { onKey(.delete) }
        }
    }

    private func key(_ content: some View, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
