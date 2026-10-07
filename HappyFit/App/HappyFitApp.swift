import SwiftUI
import SwiftData

/// Punto di ingresso dell'app iOS.
@main
struct HappyFitApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try PersistenceController.makeContainer()
            // Catalogo iniziale al primo avvio.
            try ExerciseCatalog.seedIfNeeded(in: container.mainContext)
        } catch {
            fatalError("Impossibile aprire il database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
