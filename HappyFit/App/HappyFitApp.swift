import SwiftUI
import SwiftData

/// Punto di ingresso dell'app iOS.
@main
struct HappyFitApp: App {
    private let container: ModelContainer
    private let sync: PhoneSyncService?

    init() {
        do {
            container = try PersistenceController.makeContainer()
            // Catalogo iniziale al primo avvio.
            try ExerciseCatalog.seedIfNeeded(in: container.mainContext)
        } catch {
            fatalError("Impossibile aprire il database: \(error)")
        }
        // Il servizio parte qui (non in una vista) perché l'app può essere avviata in background da un messaggio del Watch.
        // Non parte nei test e nelle schermate di collaudo, che usano dati propri.
        #if DEBUG
        let isDebugScreen = DebugLaunch.screen != nil
        #else
        let isDebugScreen = false
        #endif
        let isTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isDebugScreen || isTest {
            sync = nil
        } else {
            #if DEBUG
            SyncDebugLaunch.seedSessionIfRequested(in: container)
            #endif
            let service = PhoneSyncService(context: container.mainContext, transport: WCSessionTransport())
            ActiveWorkoutViewModel.defaultRestSync = service
            service.start()
            sync = service
            #if DEBUG
            SyncDebugLaunch.scheduleAutoCompleteIfRequested(in: container)
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                #if DEBUG
                if let screen = DebugLaunch.screen {
                    DebugScreenView(name: screen)
                } else {
                    RootView().modelContainer(container)
                }
                #else
                RootView().modelContainer(container)
                #endif
            }
        }
    }
}
