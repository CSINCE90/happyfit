import Foundation
import Observation
import SwiftData

/// Gestione della lista schede e dell'editor di una scheda.
@MainActor
@Observable
final class TemplatesViewModel {
    private let service: WorkoutService
    private let defaults: UserDefaults
    var errorMessage: String?

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.service = WorkoutService(context: context)
        self.defaults = defaults
    }

    // MARK: Lista

    @discardableResult
    func create(name: String) -> WorkoutTemplate? {
        run { try service.createTemplate(name: name) }
    }

    @discardableResult
    func rename(_ template: WorkoutTemplate, to name: String) -> Bool {
        run { try service.renameTemplate(template, to: name) } != nil
    }

    @discardableResult
    func duplicate(_ template: WorkoutTemplate) -> WorkoutTemplate? {
        run { try service.duplicateTemplate(template) }
    }

    func delete(_ template: WorkoutTemplate) {
        run { try service.removeTemplate(template) }
    }

    /// `templates` è l'elenco attualmente mostrato (ordinato).
    func move(_ templates: [WorkoutTemplate], from source: IndexSet, to destination: Int) {
        var reordered = templates
        reordered.move(fromOffsets: source, toOffset: destination)
        run { try service.reorderTemplates(reordered) }
    }

    // MARK: Editor

    func addExercise(_ exercise: Exercise, to template: WorkoutTemplate) {
        run {
            try service.addExercise(
                exercise,
                to: template,
                restSeconds: exercise.defaultRestSeconds ?? AppSettings.defaultRestSeconds(defaults)
            )
        }
    }

    func removeExercises(of template: WorkoutTemplate, at offsets: IndexSet) {
        let rows = template.sortedExercises
        for index in offsets { run { try service.removeTemplateExercise(rows[index]) } }
    }

    func moveExercises(of template: WorkoutTemplate, from source: IndexSet, to destination: Int) {
        var rows = template.sortedExercises
        rows.move(fromOffsets: source, toOffset: destination)
        run { try service.reorderTemplateExercises(rows) }
    }

    func update(_ row: TemplateExercise, sets: Int? = nil, reps: Int? = nil, restSeconds: Int? = nil) {
        run { try service.updateTemplateExercise(row, sets: sets, reps: reps, restSeconds: restSeconds) }
    }

    @discardableResult
    private func run<T>(_ work: () throws -> T) -> T? {
        do {
            return try work()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
