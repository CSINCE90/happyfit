import SwiftUI

/// Sessione attiva: esercizio e serie mostrati, peso e ripetizioni grandi, "Completa serie" sempre visibile.
struct SessionView: View {
    @Environment(\.palette) private var palette
    @Bindable var viewModel: WatchSessionViewModel
    @FocusState private var crownFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.s) {
            // Se lo spazio non basta: prima sparisce "ultima volta", poi i valori si rimpiccioliscono.
            // Il pulsante "Completa serie" resta sempre fuori da questa scelta, quindi sempre visibile.
            ViewThatFits(in: .vertical) {
                details(showPrevious: true, valueFont: .hfNumber)
                details(showPrevious: false, valueFont: .hfNumber)
                details(showPrevious: false, valueFont: .system(.title3, design: .rounded, weight: .black).monospacedDigit())
                details(showPrevious: false, valueFont: .system(.headline, design: .rounded, weight: .black).monospacedDigit(), compactHeader: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Button("Completa serie") { viewModel.completeShownSet() }
                .buttonStyle(WatchPrimaryButtonStyle())
        }
        .focusable(viewModel.selectedField != nil)
        .focused($crownFocused)
        .digitalCrownRotation(
            Binding(get: { viewModel.crownValue }, set: { viewModel.crownValue = $0 }),
            from: viewModel.crownRange.lowerBound,
            through: viewModel.crownRange.upperBound,
            by: viewModel.crownStep,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: viewModel.selectedField) { _, field in crownFocused = field != nil }
    }

    @ViewBuilder
    private func details(showPrevious: Bool, valueFont: Font, compactHeader: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let exercise = viewModel.shownExercise {
                Text(exercise.exercise.name)
                    .font(compactHeader ? .hfHeadline : .hfTitle)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(viewModel.setLabel)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                let progress = SessionLogic.progress(exercise)
                WatchSetProgress(completed: progress.completed, total: progress.total)
            }
            if let set = viewModel.shownSet {
                HStack(spacing: Spacing.s) {
                    WatchValueTile(
                        value: WatchSessionViewModel.weightText(set.weightKg), unit: "kg", label: "Peso",
                        isSelected: viewModel.selectedField == .weight, valueFont: valueFont
                    ) { viewModel.select(.weight) }
                    WatchValueTile(
                        value: "\(set.reps)", unit: "rip", label: "Ripetizioni",
                        isSelected: viewModel.selectedField == .reps, valueFont: valueFont
                    ) { viewModel.select(.reps) }
                }
            }
            if let field = viewModel.selectedField {
                // Dice cosa sta cambiando la Crown (al posto dell'ultima volta).
                Text(field == .weight ? "Corona: peso ±2,5 kg" : "Corona: ripetizioni ±1")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(palette.accentText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if showPrevious, let previous = viewModel.previousSummary {
                Text(previous)
                    .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

#if DEBUG
#Preview("Peso selezionato") {
    let viewModel = WatchSessionViewModel(remote: InMemoryWorkoutRemote(session: WatchSampleData.session), notifications: SilentRestNotifications())
    viewModel.select(.weight)
    return SessionView(viewModel: viewModel).happyFitTheme(accent: .default)
}
#endif
