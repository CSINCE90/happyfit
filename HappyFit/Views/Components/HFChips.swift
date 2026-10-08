import SwiftUI

/// Chip a capsula di un gruppo muscolare: colore del gruppo più il nome (il colore non è mai l'unico segnale).
struct MuscleChip: View {
    @Environment(\.palette) private var palette
    let group: MuscleGroup

    var body: some View {
        Text(group.displayName)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(palette.onMuscle)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(palette.muscleFill(group), in: Capsule())
    }
}

/// Chip di filtro selezionabile (accento pieno quando attivo, con ✓).
struct FilterChip: View {
    @Environment(\.palette) private var palette
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if isOn { Image(systemName: "checkmark").font(.caption.weight(.black)) }
                Text(title).lineLimit(1)
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(isOn ? palette.onAccent : palette.textPrimary)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: TouchTarget.minimum)
            .background(isOn ? palette.accent : palette.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? palette.accentOutline : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Disposizione a capo per i chip: va su più righe invece di uscire dallo schermo.
struct ChipFlow: Layout {
    var spacing: CGFloat = Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Chip dei gruppi muscolari presenti in un elenco di esercizi (senza ripetizioni, nell'ordine del catalogo).
struct MuscleChipsView: View {
    let groups: [MuscleGroup]

    init(exercises: [Exercise?]) {
        let present = Set(exercises.compactMap { $0?.muscleGroup })
        groups = MuscleGroup.allCases.filter { present.contains($0) }
    }

    var body: some View {
        if !groups.isEmpty {
            ChipFlow {
                ForEach(groups, id: \.self) { MuscleChip(group: $0) }
            }
        }
    }
}
