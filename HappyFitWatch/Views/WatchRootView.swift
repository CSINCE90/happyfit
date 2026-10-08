import SwiftUI

/// Radice dell'app Watch: messaggio senza sessione, sessione attiva, recupero o allenamento completato.
struct WatchRootView: View {
    @Bindable var viewModel: WatchSessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    /// Pagina verticale: 0 = serie, 1 = elenco degli esercizi.
    @State private var page = 0

    /// Colore d'accento scelto sull'iPhone (Volt finché non arriva una scelta).
    private var accent: AccentPreset { viewModel.remote.accent }

    var body: some View {
        content
            // Controlli di sistema (chiusura dei fogli, indicatore delle pagine) su grigio neutro: la X bianca resta
            // leggibile. I componenti dell'app usano colori espliciti della palette, quindi non cambiano.
            .tint(Palette(isDark: true, accentPreset: accent).raised)
            .happyFitTheme(accent: accent)
            .preferredColorScheme(.dark)
            // Un recupero partito (o cambiato) sull'iPhone compare anche qui.
            .onChange(of: viewModel.remoteRestVersion) { _, _ in viewModel.adoptRemoteRest() }
            // All'apertura e al ritorno in primo piano si chiede lo stato aggiornato all'iPhone.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.remote.requestState() }
            }
            .task { viewModel.remote.requestState() }
    }

    /// Con l'iPhone non raggiungibile si vede l'ultimo stato noto, con una fascia chiara (icona e testo).
    /// La fascia fa parte del layout di ogni pagina (non è un inset: nelle pagine verticali non riduce lo spazio e coprirebbe il contenuto).
    @ViewBuilder
    private var banner: some View {
        if case .offline(let lastUpdate) = viewModel.remote.connection {
            OfflineBanner(lastUpdate: lastUpdate)
        }
    }

    private func page<V: View>(@ViewBuilder _ view: () -> V) -> some View {
        VStack(spacing: Spacing.xs) {
            banner
            view()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screen {
        case .noSession:
            page { WatchMessageView(systemImage: "iphone", title: "Avvia un allenamento dall'iPhone", detail: nil) }
        case .allDone:
            page { WatchMessageView(systemImage: "checkmark.circle.fill", title: "Allenamento completato", detail: "Termina dall'iPhone") }
        case .set:
            Group {
                if viewModel.restTimer != nil {
                    page { RestView(viewModel: viewModel) }
                } else {
                    // Pagine verticali (HIG watchOS): la serie, poi l'elenco per scegliere l'esercizio da mostrare.
                    TabView(selection: $page) {
                        page { SessionView(viewModel: viewModel) }.tag(0)
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
