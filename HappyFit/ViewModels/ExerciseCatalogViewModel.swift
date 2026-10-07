import Foundation
import Observation
import SwiftData

/// Catalogo esercizi: ricerca, filtro per gruppo, creazione, modifica e archiviazione.
@MainActor
@Observable
final class ExerciseCatalogViewModel {
    private let service: WorkoutService
    var searchText = ""
    var selectedGroup: MuscleGroup?
    var errorMessage: String?

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
