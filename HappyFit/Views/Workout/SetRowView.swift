import SwiftUI

/// Riga di una serie: tipo, peso, ripetizioni e spunta. Controlli grandi per l'uso con una mano.
struct SetRowView: View {
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
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            HStack(spacing: 8) {
                typeMenu
                if typeSize.isAccessibilitySize { Spacer() }
                if typeSize.isAccessibilitySize { checkButton }
            }
            stepperControl(
                value: Formatting.weight(entry.weightKg), unit: "kg",
                minus: { onWeight(-1) }, plus: { onWeight(1) }, edit: onEditWeight,
                label: "Peso"
            )
            stepperControl(
                value: "\(entry.reps)", unit: "rip",
                minus: { onReps(-1) }, plus: { onReps(1) }, edit: onEditReps,
                label: "Ripetizioni"
            )
            if !typeSize.isAccessibilitySize { checkButton }
        }
        .padding(.vertical, 4)
        .opacity(entry.isCompleted ? 0.75 : 1)
    }

    private var typeMenu: some View {
        Menu {
            Picker("Tipo", selection: Binding(get: { entry.type }, set: onType)) {
                ForEach(SetType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Button("Elimina serie", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            VStack(spacing: 0) {
                Text("\(index)").font(.headline)
                Text(entry.type.shortName).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 44)
            .background(entry.type.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("Serie \(index), \(entry.type.displayName)")
    }

    private func stepperControl(value: String, unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void, edit: @escaping () -> Void, label: String) -> some View {
        HStack(spacing: 4) {
            Button(action: minus) { Image(systemName: "minus").frame(width: 40, height: 48) }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(label) meno")
            Button(action: edit) {
                VStack(spacing: 0) {
                    Text(value).font(.title3.monospacedDigit().bold())
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(minWidth: 44)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label) \(value) \(unit)")
            Button(action: plus) { Image(systemName: "plus").frame(width: 40, height: 48) }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(label) più")
        }
    }

    private var checkButton: some View {
        Button(action: onToggle) {
            Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 36))
                .foregroundStyle(entry.isCompleted ? Color.green : Color.secondary)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isCompleted ? "Serie completata" : "Completa serie")
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
