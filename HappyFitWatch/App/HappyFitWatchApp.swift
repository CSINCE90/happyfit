import SwiftUI
import UserNotifications
import WatchKit

/// Punto di ingresso dell'app watchOS: telecomando della sessione avviata sull'iPhone.
@main
struct HappyFitWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var viewModel: WatchSessionViewModel
    /// Con l'app in primo piano l'avviso di fine recupero non si mostra (vibra già l'app).
    private static let notificationDelegate = ForegroundNotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
        let notifications = LocalRestNotifications()
        #if DEBUG
        if WatchDebugLaunch.screen != nil {
            // Schermate di collaudo: dati di esempio, nessuna connessione.
            _viewModel = State(initialValue: WatchDebugLaunch.makeViewModel())
            return
        }
        #endif
        // La sessione WatchConnectivity si attiva qui, all'avvio: i dati arrivano anche se l'app parte in background.
        let remote = ConnectivityWorkoutRemote(transport: WCSessionTransport(), restNotifier: notifications)
        remote.start()
        let model = WatchSessionViewModel(remote: remote, notifications: notifications)
        _viewModel = State(initialValue: model)
        #if DEBUG
        WatchDebugLaunch.scheduleAutoCompleteIfRequested(viewModel: model)
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

/// Attività in background di WatchConnectivity: il sistema sveglia l'app per consegnare lo stato dell'iPhone.
/// Vanno sempre completate (altrimenti si consuma il budget in background).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if task is WKWatchConnectivityRefreshBackgroundTask {
                // La sessione è già attiva (avviata in init): lo stato viene consegnato al suo delegato. Si chiude poco dopo.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    task.setTaskCompletedWithSnapshot(false)
                }
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
