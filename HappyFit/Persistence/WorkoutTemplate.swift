import Foundation
import SwiftData

/// Scheda di allenamento riutilizzabile.
@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    /// Cancellare il template elimina le sue righe, non gli esercizi.
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise] = []

    init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }

    /// Esercizi ordinati (SwiftData non garantisce l'ordine delle relazioni to-many).
    var sortedExercises: [TemplateExercise] {
        exercises.sorted { $0.order < $1.order }
    }
}

/// Riga di un template: esercizio con obiettivi.
@Model
final class TemplateExercise {
    var id: UUID = UUID()
    var order: Int = 0
    var targetSets: Int = 3
    var targetReps: Int = 10
    var restSeconds: Int = 90
    var template: WorkoutTemplate?
    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    init(id: UUID = UUID(), exercise: Exercise, order: Int, targetSets: Int, targetReps: Int, restSeconds: Int) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restSeconds = restSeconds
    }
}
