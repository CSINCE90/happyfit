import SwiftUI

/// Riga di una serie su due righe: sopra tipo e spunta, sotto peso e ripetizioni.
/// Pensata per l'uso con una mano: aree di tocco ampie e nessun elemento fuori schermo.
struct SetRowView: View {
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
            // Affiancati se c'è spazio, altrimenti uno sotto l'altro (testo molto grande).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { weightControl; repsControl }
                VStack(spacing: 10) { weightControl; repsControl }
            }
        }
        .padding(.vertical, 6)
        .opacity(entry.isCompleted ? 0.75 : 1)
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
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Serie \(index)").font(.headline)
                    Text(entry.type.displayName).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(entry.type.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Serie \(index), \(entry.type.displayName)")
    }

    private var checkButton: some View {
        Button(action: onToggle) {
            Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 40))
                .foregroundStyle(entry.isCompleted ? Color.green : Color.secondary)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isCompleted ? "Serie completata" : "Completa serie")
    }
}

/// Controllo − valore + (peso o ripetizioni): pulsanti da almeno 44 pt, valore al centro che apre il tastierino.
struct ValueControl: View {
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
                        .font(.title3.monospacedDigit().bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
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
                .font(.headline)
                .frame(width: 48, height: 48)
                .background(.fill.tertiary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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

    var color: Color {
        switch self {
        case .warmup: return .orange
        case .normal: return .accentColor
        case .failure: return .red
        }
    }
}
