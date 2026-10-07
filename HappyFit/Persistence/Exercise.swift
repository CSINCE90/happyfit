import Foundation
import SwiftData

/// Esercizio del catalogo. Non ha relazioni inverse: cancellare sessioni o template non lo tocca.
@Model
final class Exercise {
    var id: UUID = UUID()
    /// Unicità case-insensitive garantita da WorkoutService; qui è solo l'ultima rete di sicurezza.
    @Attribute(.unique) var name: String = ""
    var muscleGroup: MuscleGroup?
    /// Gli esercizi non si cancellano: si archiviano (lo storico li mantiene).
    var isArchived: Bool = false

    init(id: UUID = UUID(), name: String, muscleGroup: MuscleGroup? = nil, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.isArchived = isArchived
    }

    func toDTO() -> ExerciseDTO {
        ExerciseDTO(id: id, name: name)
    }
}
