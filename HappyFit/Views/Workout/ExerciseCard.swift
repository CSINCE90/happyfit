import SwiftUI

/// Card di un esercizio nella sessione: nome, valori dell'ultima volta, serie.
struct ExerciseCard: View {
    @Environment(\.palette) private var palette
    let item: SessionExercise
    /// Primo esercizio con serie ancora da fare (derivato nella vista che contiene le card).
    var isCurrent = false
    let viewModel: ActiveWorkoutViewModel
    let onEditNumber: (NumberTarget) -> Void
    let onEditRest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if isCurrent {
                        Eyebrow("In corso").foregroundStyle(palette.accentText)
                    }
                    Text(item.exercise?.name ?? "Esercizio")
                        .font(.hfTitle)
                        .foregroundStyle(palette.textPrimary)
                    if let previous = viewModel.previousSummary(for: item) {
                        Text("Ultima volta: \(previous)")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        Text("Nessuno storico")
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Recupero: \(Formatting.rest(item.restSeconds))", systemImage: "timer", action: onEditRest)
                    Button("Rimuovi esercizio", systemImage: "trash", role: .destructive) {
                        viewModel.removeExercise(item)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(palette.accentText)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }

            SetProgressView(completed: item.completedSets.count, total: item.sets.count)

            ForEach(Array(item.sortedSets.enumerated()), id: \.element.id) { index, entry in
                SetRowView(
                    index: index + 1,
                    entry: entry,
                    onToggle: { viewModel.toggleComplete(entry) },
                    onWeight: { viewModel.adjustWeight(entry, direction: $0) },
                    onReps: { viewModel.adjustReps(entry, delta: $0) },
                    onEditWeight: { onEditNumber(NumberTarget(entry: entry, isWeight: true)) },
                    onEditReps: { onEditNumber(NumberTarget(entry: entry, isWeight: false)) },
                    onType: { viewModel.setType(entry, $0) },
                    onDelete: { viewModel.removeSet(entry) }
                )
            }

            // Affiancati se c'è spazio, altrimenti uno sotto l'altro.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { addSetButton; Spacer(minLength: 12); restButton }
                VStack(spacing: 12) { addSetButton; restButton }
            }
        }
        .hfCard(highlighted: isCurrent)
    }

    private var addSetButton: some View {
        Button {
            viewModel.addSet(to: item)
        } label: {
            Label("Serie", systemImage: "plus")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Spacing.s)
        }
        .buttonStyle(.hfSecondary)
    }

    private var restButton: some View {
        Button(action: onEditRest) {
            Label(Formatting.rest(item.restSeconds), systemImage: "timer")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Spacing.s)
        }
        .buttonStyle(.hfSecondary)
    }
}
