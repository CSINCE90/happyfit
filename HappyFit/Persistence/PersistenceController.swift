import Foundation
import SwiftData

/// Schema SwiftData e creazione del container.
enum PersistenceController {
    static let models: [any PersistentModel.Type] = [
        Exercise.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        WorkoutSession.self,
        SessionExercise.self,
        SetEntry.self
    ]

    static var schema: Schema { Schema(models) }

    /// Container su disco, oppure in memoria (test e anteprime).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
