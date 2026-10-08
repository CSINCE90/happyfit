import SwiftUI

/// Radice dell'app Watch: messaggio senza sessione, sessione attiva, recupero o allenamento completato.
struct WatchRootView: View {
    @Bindable var viewModel: WatchSessionViewModel
    /// Pagina verticale: 0 = serie, 1 = elenco degli esercizi.
    @State private var page = 0
    /// Colore d'accento (per ora fisso; nello step 5 arriverà dalle Impostazioni dell'iPhone).
    var accent: AccentPreset = .default

    var body: some View {
        content
            // Controlli di sistema (chiusura dei fogli, indicatore delle pagine) su grigio neutro: la X bianca resta
            // leggibile. I componenti dell'app usano colori espliciti della palette, quindi non cambiano.
            .tint(Palette(isDark: true, accentPreset: accent).raised)
            .happyFitTheme(accent: accent)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screen {
        case .noSession:
            WatchMessageView(systemImage: "iphone", title: "Avvia un allenamento dall'iPhone", detail: nil)
        case .allDone:
            WatchMessageView(systemImage: "checkmark.circle.fill", title: "Allenamento completato", detail: "Termina dall'iPhone")
        case .set:
            Group {
                if viewModel.restTimer != nil {
                    RestView(viewModel: viewModel)
                } else {
                    // Pagine verticali (HIG watchOS): la serie, poi l'elenco per scegliere l'esercizio da mostrare.
                    TabView(selection: $page) {
                        SessionView(viewModel: viewModel).tag(0)
                        NavigationStack {
                            ExerciseListView(viewModel: viewModel) { page = 0 }
                        }
                        .tag(1)
                    }
                    .tabViewStyle(.verticalPage)
                }
            }
            .sheet(isPresented: $viewModel.showPermissionExplanation) {
                PermissionExplanationView(viewModel: viewModel)
            }
        }
    }
}

#if DEBUG
#Preview("Sessione") {
    WatchRootView(viewModel: WatchSessionViewModel(remote: InMemoryWorkoutRemote(session: WatchSampleData.session), notifications: SilentRestNotifications()))
}

#Preview("Nessuna sessione") {
    WatchRootView(viewModel: WatchSessionViewModel(remote: InMemoryWorkoutRemote(session: nil), notifications: SilentRestNotifications()))
}

#Preview("Completato") {
    WatchRootView(viewModel: WatchSessionViewModel(remote: InMemoryWorkoutRemote(session: WatchSampleData.completedSession), notifications: SilentRestNotifications()))
}
#endif
