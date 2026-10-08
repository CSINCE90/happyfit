import Foundation
import Observation
import SwiftData

/// Cosa fare quando l'utente chiede di eliminare un esercizio.
enum ExerciseDeletionPlan: Equatable {
    /// Mai usato: si elimina davvero, dopo conferma.
    case confirmDelete(Exercise)
    /// Compare in allenamenti: non si elimina, si propone di archiviare.
    case blocked(Exercise, sessionCount: Int)
    /// Compare solo in schede: si elenca dove e si chiede conferma prima di toglierlo da lì.
    case confirmRemoveFromTemplates(Exercise, templates: [String])

    var exercise: Exercise {
        switch self {
        case .confirmDelete(let e), .blocked(let e, _), .confirmRemoveFromTemplates(let e, _): return e
        }
    }
}

/// Catalogo esercizi: ricerca, filtro per gruppo, creazione, modifica e archiviazione.
@MainActor
@Observable
final class ExerciseCatalogViewModel {
    private let service: WorkoutService
    var searchText = ""
    var selectedGroup: MuscleGroup?
    var errorMessage: String?
    var deletionPlan: ExerciseDeletionPlan?

    init(context: ModelContext) {
        self.service = WorkoutService(context: context)
    }

    /// Esercizi attivi che soddisfano ricerca e filtro, ordinati per nome.
    func visible(from all: [Exercise]) -> [Exercise] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return all
            .filter { !$0.isArchived }
            .filter { selectedGroup == nil || $0.muscleGroup == selectedGroup }
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func archived(from all: [Exercise]) -> [Exercise] {
        all.filter(\.isArchived).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func create(name: String, group: MuscleGroup?, defaultRestSeconds: Int?) -> Bool {
        run { try service.createExercise(name: name, muscleGroup: group, defaultRestSeconds: defaultRestSeconds) }
    }

    /// Salva nome, gruppo e recupero; se il nome è duplicato non cambia nulla.
    @discardableResult
    func update(_ exercise: Exercise, name: String, group: MuscleGroup?, defaultRestSeconds: Int?) -> Bool {
        run {
            try service.renameExercise(exercise, to: name)
            try service.setMuscleGroup(exercise, group)
            try service.setDefaultRest(exercise, seconds: defaultRestSeconds)
        }
    }

    func archive(_ exercise: Exercise) {
        run { try service.archiveExercise(exercise) }
    }

    func unarchive(_ exercise: Exercise) {
        run { try service.unarchiveExercise(exercise) }
    }

    // MARK: Eliminazione

    /// Decide cosa fare in base a dove compare l'esercizio (vedi `ExerciseDeletionPlan`).
    func requestDelete(_ exercise: Exercise) {
        do {
            let usage = try service.exerciseUsage(exercise)
            if usage.sessionCount > 0 {
                deletionPlan = .blocked(exercise, sessionCount: usage.sessionCount)
            } else if !usage.templateNames.isEmpty {
                deletionPlan = .confirmRemoveFromTemplates(exercise, templates: usage.templateNames)
            } else {
                deletionPlan = .confirmDelete(exercise)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Esegue l'eliminazione confermata. Ritorna true se l'esercizio è stato eliminato.
    @discardableResult
    func confirmDeletion() -> Bool {
        guard let plan = deletionPlan else { return false }
        deletionPlan = nil
        switch plan {
        case .blocked:
            return false
        case .confirmDelete(let exercise):
            return run { try service.deleteExercise(exercise) }
        case .confirmRemoveFromTemplates(let exercise, _):
            return run { try service.deleteExercise(exercise, removingFromTemplates: true) }
        }
    }

    /// Da un esercizio che non si può eliminare: lo archivia.
    @discardableResult
    func archiveInsteadOfDeleting() -> Bool {
        guard case .blocked(let exercise, _) = deletionPlan else { return false }
        deletionPlan = nil
        return run { try service.archiveExercise(exercise) }
    }

    func cancelDeletion() {
        deletionPlan = nil
    }

    @discardableResult
    private func run(_ work: () throws -> some Any) -> Bool {
        do {
            _ = try work()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
