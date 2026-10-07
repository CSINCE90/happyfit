import Foundation
import SwiftData

/// Catalogo iniziale di esercizi comuni, caricato al primo avvio.
enum ExerciseCatalog {
    static let initialExercises: [(name: String, group: MuscleGroup)] = [
        // Petto
        ("Panca piana con bilanciere", .petto),
        ("Panca inclinata con manubri", .petto),
        ("Croci ai cavi", .petto),
        ("Piegamenti sulle braccia", .petto),
        // Schiena
        ("Trazioni alla sbarra", .schiena),
        ("Lat machine", .schiena),
        ("Rematore con bilanciere", .schiena),
        ("Pulley basso", .schiena),
        ("Stacco da terra", .schiena),
        // Gambe
        ("Squat con bilanciere", .gambe),
        ("Leg press", .gambe),
        ("Affondi con manubri", .gambe),
        ("Leg extension", .gambe),
        ("Leg curl", .gambe),
        ("Calf in piedi", .gambe),
        // Spalle
        ("Military press", .spalle),
        ("Alzate laterali", .spalle),
        ("Alzate posteriori", .spalle),
        ("Arnold press", .spalle),
        // Braccia
        ("Curl con bilanciere", .braccia),
        ("Curl a martello", .braccia),
        ("Push down ai cavi", .braccia),
        ("French press", .braccia),
        // Core
        ("Crunch", .core),
        ("Plank", .core),
        ("Sollevamento gambe alla sbarra", .core)
    ]

    /// Inserisce il catalogo solo se non esiste ancora nessun esercizio. Ritorna true se ha caricato.
    @discardableResult
    static func seedIfNeeded(in context: ModelContext) throws -> Bool {
        let existing = try context.fetchCount(FetchDescriptor<Exercise>())
        guard existing == 0 else { return false }
        for item in initialExercises {
            context.insert(Exercise(name: item.name, muscleGroup: item.group))
        }
        try context.save()
        return true
    }
}
