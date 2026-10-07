import Foundation
import SwiftData

/// Allenamento svolto (o in corso se `endedAt` è nil).
@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    /// Template di origine: se viene cancellato il riferimento si azzera.
    @Relationship(deleteRule: .nullify)
    var template: WorkoutTemplate?
    /// Cancellare la sessione elimina esercizi di sessione e serie, non gli esercizi del catalogo.
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise] = []

    init(id: UUID = UUID(), name: String, startedAt: Date = Date(), endedAt: Date? = nil, template: WorkoutTemplate? = nil) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.template = template
    }

    var isOpen: Bool { endedAt == nil }

    var sortedExercises: [SessionExercise] {
        exercises.sorted { $0.order < $1.order }
    }
}

/// Esercizio dentro una sessione.
@Model
final class SessionExercise {
    var id: UUID = UUID()
    var order: Int = 0
    var session: WorkoutSession?
    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.sessionExercise)
    var sets: [SetEntry] = []

    init(id: UUID = UUID(), exercise: Exercise?, order: Int) {
        self.id = id
        self.exercise = exercise
        self.order = order
    }

    var sortedSets: [SetEntry] {
        sets.sorted { $0.order < $1.order }
    }

    /// Solo le serie completate, in ordine.
    var completedSets: [SetEntry] {
        sortedSets.filter { $0.completedAt != nil }
    }
}

/// Singola serie.
@Model
final class SetEntry {
    var id: UUID = UUID()
    var order: Int = 0
    var weightKg: Double = 0
    var reps: Int = 0
    var type: SetType = SetType.normal
    var completedAt: Date?
    var sessionExercise: SessionExercise?

    init(id: UUID = UUID(), order: Int, weightKg: Double = 0, reps: Int = 0, type: SetType = .normal, completedAt: Date? = nil) {
        self.id = id
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.type = type
        self.completedAt = completedAt
    }

    var isCompleted: Bool { completedAt != nil }
}

// MARK: - Conversione modello -> DTO

extension SetEntry {
    func toDTO() -> SetEntryDTO {
        SetEntryDTO(id: id, order: order, weightKg: weightKg, reps: reps, type: type, completedAt: completedAt)
    }

    convenience init(dto: SetEntryDTO) {
        self.init(id: dto.id, order: dto.order, weightKg: dto.weightKg, reps: dto.reps, type: dto.type, completedAt: dto.completedAt)
    }
}

extension SessionExercise {
    /// Nil se l'esercizio del catalogo non è più disponibile.
    func toDTO() -> SessionExerciseDTO? {
        guard let exercise else { return nil }
        return SessionExerciseDTO(id: id, exercise: exercise.toDTO(), order: order, sets: sortedSets.map { $0.toDTO() })
    }
}
