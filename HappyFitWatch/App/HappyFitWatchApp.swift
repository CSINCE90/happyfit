import SwiftUI
import UserNotifications

/// Punto di ingresso dell'app watchOS: telecomando della sessione avviata sull'iPhone.
@main
struct HappyFitWatchApp: App {
    @State private var viewModel: WatchSessionViewModel
    /// Con l'app in primo piano l'avviso di fine recupero non si mostra (vibra già l'app).
    private static let notificationDelegate = ForegroundNotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
        #if DEBUG
        _viewModel = State(initialValue: WatchDebugLaunch.makeViewModel())
        #else
        // Nessuna sincronizzazione in questo step: senza iPhone collegato non c'è sessione.
        _viewModel = State(initialValue: WatchSessionViewModel(
            remote: InMemoryWorkoutRemote(session: nil),
            notifications: LocalRestNotifications()
        ))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            Group {
                if WatchDebugLaunch.screen == "list" {
                    NavigationStack { ExerciseListView(viewModel: viewModel) }
                        .happyFitTheme(accent: .default)
                        .preferredColorScheme(.dark)
                } else {
                    WatchRootView(viewModel: viewModel)
                }
            }
            .dynamicTypeSize(WatchDebugLaunch.textSize ?? .large)
            #else
            WatchRootView(viewModel: viewModel)
            #endif
        }
    }
}
