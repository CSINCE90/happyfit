import SwiftUI

/// Riga di una serie su due righe: sopra tipo e spunta, sotto peso e ripetizioni.
/// Pensata per l'uso con una mano: aree di tocco ampie e nessun elemento fuori schermo.
struct SetRowView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let index: Int
    let entry: SetEntry
    let onToggle: () -> Void
    let onWeight: (Int) -> Void
    let onReps: (Int) -> Void
    let onEditWeight: () -> Void
    let onEditReps: () -> Void
    let onType: (SetType) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                typeMenu
                checkButton
            }
            // Affiancati sempre (stesso layout su ogni riga); uno sotto l'altro solo con testo di accessibilità.
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) { weightControl; repsControl }
            } else {
                HStack(spacing: Spacing.m) { weightControl; repsControl }
            }
        }
        .padding(.vertical, 6)
        .opacity(entry.isCompleted ? 0.75 : 1)
        // Vibrazione leggera al tocco: alla spunta e a ogni cambio di peso o ripetizioni (spenta con "Riduci movimento").
        .sensoryFeedback(trigger: entry.isCompleted) { _, completed in
            reduceMotion || !completed ? nil : .impact(weight: .light)
        }
        .sensoryFeedback(trigger: entry.weightKg) { _, _ in reduceMotion ? nil : .selection }
        .sensoryFeedback(trigger: entry.reps) { _, _ in reduceMotion ? nil : .selection }
    }

    private var weightControl: some View {
        ValueControl(
            value: Formatting.weight(entry.weightKg), unit: "kg", label: "Peso",
            onMinus: { onWeight(-1) }, onPlus: { onWeight(1) }, onEdit: onEditWeight
        )
    }

    private var repsControl: some View {
        ValueControl(
            value: "\(entry.reps)", unit: "rip", label: "Ripetizioni",
            onMinus: { onReps(-1) }, onPlus: { onReps(1) }, onEdit: onEditReps
        )
    }

    /// Badge con numero e tipo: larghezza flessibile, il testo può andare a capo ma non si tronca.
    private var typeMenu: some View {
        Menu {
            Picker("Tipo", selection: Binding(get: { entry.type }, set: onType)) {
                ForEach(SetType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Button("Elimina serie", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Serie \(index)").font(.hfHeadline).foregroundStyle(palette.textPrimary)
                    // Il tipo si legge da icona e parola, non dal colore.
                    Label {
                        Text(entry.type.displayName)
                    } icon: {
                        if let symbol = entry.type.symbol { Image(systemName: symbol) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Serie \(index), \(entry.type.displayName)")
    }

    private var checkButton: some View {
        Button(action: onToggle) {
            CompletionCircle(isCompleted: entry.isCompleted)
                .frame(width: 44, height: 44)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.55), value: entry.isCompleted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isCompleted ? "Serie completata" : "Completa serie")
    }
}

/// Controllo − valore + (peso o ripetizioni): pulsanti da almeno 44 pt, valore al centro che apre il tastierino.
struct ValueControl: View {
    @Environment(\.palette) private var palette
    let value: String
    let unit: String
    let label: String
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            StepButton(systemImage: "minus", label: "\(label) meno", action: onMinus)
            Button(action: onEdit) {
                VStack(spacing: 0) {
                    Text(value)
                        .font(.hfNumber)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Eyebrow(unit).foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label) \(value) \(unit)")
            StepButton(systemImage: "plus", label: "\(label) più", action: onPlus)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Pulsante tondo − / + con area di tocco di 48 × 48 pt.
struct StepButton: View {
    let systemImage: String
    let label: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.hfStep)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

extension SetType {
    var displayName: String {
        switch self {
        case .warmup: return "Riscaldamento"
        case .normal: return "Normale"
        case .failure: return "Cedimento"
        }
    }

    var shortName: String {
        switch self {
        case .warmup: return "risc."
        case .normal: return "norm."
        case .failure: return "ced."
        }
    }

    /// Icona del tipo (nessuna per la serie normale): il tipo non è mai indicato solo dal colore.
    var symbol: String? {
        switch self {
        case .warmup: return "thermometer.medium"
        case .normal: return nil
        case .failure: return "bolt.fill"
        }
    }
}
