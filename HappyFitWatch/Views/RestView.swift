import SwiftUI

/// Recupero a tutto schermo: tempo grande dentro l'anello, −15 / +15 / Salta.
struct RestView: View {
    @Environment(\.palette) private var palette
    let viewModel: WatchSessionViewModel

    private var progress: Double {
        guard let total = viewModel.restTimer?.totalSeconds, total > 0 else { return 0 }
        return Double(viewModel.restRemainingSeconds) / Double(total)
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            ZStack {
                WatchTimerRing(progress: progress)
                VStack(spacing: 0) {
                    Text(WatchSessionViewModel.clockText(viewModel.restRemainingSeconds))
                        .font(.hfTimer)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        // Il tempo non si tronca mai: si rimpicciolisce.
                        .minimumScaleFactor(0.3)
                    Eyebrow("Recupero")
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                }
                // Tempo ed etichetta restano dentro l'anello anche a testo grande.
                .padding(Spacing.m)
            }
            // Area quadrata quanto l'anello: il testo non può allargarsi oltre il cerchio.
            .aspectRatio(1, contentMode: .fit)
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .combine)

            // Testo se c'è spazio, altrimenti icone: i pulsanti non vanno mai a capo.
            ViewThatFits(in: .horizontal) {
                buttons(compact: false)
                buttons(compact: true)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .background(palette.background)
    }

    private func buttons(compact: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Button { viewModel.addRest(seconds: -15) } label: {
                if compact { Image(systemName: "gobackward.15") } else { Text("−15").fixedSize() }
            }
            .buttonStyle(WatchSecondaryButtonStyle())
            .accessibilityLabel("Meno 15 secondi")
            Button { viewModel.addRest(seconds: 15) } label: {
                if compact { Image(systemName: "goforward.15") } else { Text("+15").fixedSize() }
            }
            .buttonStyle(WatchSecondaryButtonStyle())
            .accessibilityLabel("Più 15 secondi")
            Button { viewModel.skipRest() } label: {
                if compact { Image(systemName: "forward.end.fill") } else { Text("Salta").fixedSize() }
            }
            .buttonStyle(WatchPrimaryButtonStyle())
            .accessibilityLabel("Salta recupero")
        }
    }
}

#if DEBUG
#Preview {
    let viewModel = WatchSessionViewModel(remote: InMemoryWorkoutRemote(session: WatchSampleData.session), notifications: SilentRestNotifications())
    viewModel.startRest(seconds: 90)
    return RestView(viewModel: viewModel).happyFitTheme(accent: .default)
}
#endif
