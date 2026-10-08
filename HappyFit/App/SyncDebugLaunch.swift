#if DEBUG
import Foundation
import OSLog
import SwiftData

/// Solo collaudo della sincronizzazione nel simulatore. Non esiste in Release.
/// `-debugSeedSession`: crea una scheda e avvia un allenamento nel database reale (se non ce n'è uno aperto).
/// `-debugCompleteAfter N`: dopo N secondi completa la prima serie incompleta come farebbe l'utente sull'iPhone.
@MainActor
enum SyncDebugLaunch {
    private static let log = Logger(subsystem: "com.csince90.happyfit", category: "sync")

    private static func value(of flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag) else { return nil }
        return args.indices.contains(index + 1) ? args[index + 1] : ""
    }

    static func seedSessionIfRequested(in container: ModelContainer) {
        guard CommandLine.arguments.contains("-debugSeedSession") else { return }
        let service = WorkoutService(context: container.mainContext)
        guard (try? service.openSession()) == nil else { return }
        let catalog = (try? service.catalog()) ?? []
        let picks = catalog.prefix(3).map { ($0, 3, 8, 90) }
        guard !picks.isEmpty, let template = try? service.createTemplate(name: "Prova Watch", exercises: Array(picks)) else { return }
        _ = try? service.startSession(from: template)
        log.debug("sessione di prova avviata")
    }

    static func scheduleAutoCompleteIfRequested(in container: ModelContainer) {
        guard let text = value(of: "-debugCompleteAfter"), let seconds = Double(text) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            let service = WorkoutService(context: container.mainContext)
            guard let session = (try? service.openSession()) ?? nil else { return }
            for item in session.sortedExercises {
                if let entry = item.sortedSets.first(where: { !$0.isCompleted }) {
                    log.notice("iPhone: serie completata alle \(Date().timeIntervalSince1970, privacy: .public)")
                    try? service.completeSet(entry)
                    return
                }
            }
        }
    }
}
#endif
