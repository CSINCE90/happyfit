import Foundation

// Strutture semplici usate per il sync iPhone <-> Watch (il Watch non usa SwiftData).

struct SetEntryDTO: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var order: Int
    var weightKg: Double
    var reps: Int
    var type: SetType
    var completedAt: Date?
}

struct ExerciseDTO: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
}

struct SessionExerciseDTO: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var exercise: ExerciseDTO
    var order: Int
    var sets: [SetEntryDTO]
}

struct WorkoutSessionDTO: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var exercises: [SessionExerciseDTO]
    /// Serie completate dell'ultima volta, per id esercizio.
    var previousSets: [UUID: [SetEntryDTO]]
}
