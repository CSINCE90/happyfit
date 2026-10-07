import SwiftUI

/// Card di un esercizio nella sessione: nome, valori dell'ultima volta, serie.
struct ExerciseCard: View {
    let item: SessionExercise
    let viewModel: ActiveWorkoutViewModel
    let onEditNumber: (NumberTarget) -> Void
    let onEditRest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.exercise?.name ?? "Esercizio")
                        .font(.title3.bold())
                    if let previous = viewModel.previousSummary(for: item) {
                        Text("Ultima volta: \(previous)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nessuno storico")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                        .frame(minWidth: 44, minHeight: 44)
                }
            }

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
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var addSetButton: some View {
        Button {
            viewModel.addSet(to: item)
        } label: {
            Label("Serie", systemImage: "plus")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
    }

    private var restButton: some View {
        Button(action: onEditRest) {
            Label(Formatting.rest(item.restSeconds), systemImage: "timer")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
    }
}
