import SwiftUI

/// Elenco degli esercizi della sessione: serve solo a scegliere quale mostrare (i dati non cambiano).
struct ExerciseListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let viewModel: WatchSessionViewModel
    /// Dopo la scelta (nell'app: torna alla pagina della serie).
    var onSelect: (() -> Void)?

    var body: some View {
        List(viewModel.exercises, id: \.id) { exercise in
            let progress = SessionLogic.progress(exercise)
            let isDone = progress.total > 0 && progress.completed == progress.total
            Button {
                viewModel.show(exerciseID: exercise.id)
                if let onSelect { onSelect() } else { dismiss() }
            } label: {
                HStack(spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.exercise.name)
                            .font(.hfHeadline)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(progress.completed)/\(progress.total) serie")
                            .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if isDone {
                        // Completato: ✓ oltre al colore.
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                            .accessibilityLabel("Completato")
                    } else if exercise.id == viewModel.shownExercise?.id {
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(palette.accentText)
                            .accessibilityLabel("Mostrato ora")
                    }
                }
                .frame(minHeight: TouchTarget.minimum)
            }
        }
        .navigationTitle("Esercizi")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ExerciseListView(viewModel: WatchSessionViewModel(remote: InMemoryWorkoutRemote(session: WatchSampleData.session), notifications: SilentRestNotifications()))
    }
    .happyFitTheme(accent: .default)
}
#endif
