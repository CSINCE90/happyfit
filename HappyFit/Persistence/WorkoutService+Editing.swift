import Foundation
import SwiftData

/// Dove compare un esercizio del catalogo.
struct ExerciseUsage: Equatable {
    /// Allenamenti (in corso o nello storico) che lo contengono.
    var sessionCount: Int
    /// Nomi delle schede che lo contengono.
    var templateNames: [String]

    var isUnused: Bool { sessionCount == 0 && templateNames.isEmpty }
}

/// Estensioni per il CRUD completo: eliminazione sicura di schede ed esercizi, modifica dello storico.
extension WorkoutService {
    // MARK: - Schede

    /// Elimina la scheda scollegandola prima dalle sessioni che l'hanno usata (lo storico non cambia).
    func removeTemplate(_ template: WorkoutTemplate) throws {
        let id = template.id
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.template?.id == id }))
        for session in sessions { session.template = nil }
        try deleteTemplate(template)
    }

    // MARK: - Catalogo

    func exerciseUsage(_ exercise: Exercise) throws -> ExerciseUsage {
        let id = exercise.id
        let items = try context.fetch(FetchDescriptor<SessionExercise>(predicate: #Predicate { $0.exercise?.id == id }))
        let sessionIDs = Set(items.compactMap { $0.session?.id })
        let rows = try context.fetch(FetchDescriptor<TemplateExercise>(predicate: #Predicate { $0.exercise?.id == id }))
        let names = Set(rows.compactMap { $0.template?.name }).sorted()
        return ExerciseUsage(sessionCount: sessionIDs.count, templateNames: names)
    }

    /// Elimina davvero un esercizio mai usato. Se compare in un allenamento lancia `exerciseUsedInSessions`
    /// (si può solo archiviare). Se compare solo in schede lancia `exerciseUsedInTemplates`, a meno che
    /// `removingFromTemplates` sia true: in quel caso lo toglie prima dalle schede.
    func deleteExercise(_ exercise: Exercise, removingFromTemplates: Bool = false) throws {
        let usage = try exerciseUsage(exercise)
        if usage.sessionCount > 0 {
            throw WorkoutServiceError.exerciseUsedInSessions(name: exercise.name, count: usage.sessionCount)
        }
        if !usage.templateNames.isEmpty && !removingFromTemplates {
            throw WorkoutServiceError.exerciseUsedInTemplates(name: exercise.name, templates: usage.templateNames)
        }

        let id = exercise.id
        let rows = try context.fetch(FetchDescriptor<TemplateExercise>(predicate: #Predicate { $0.exercise?.id == id }))
        let removed = Set(rows.map(\.persistentModelID))
        var templates: [WorkoutTemplate] = []
        for row in rows {
            if let template = row.template, !templates.contains(where: { $0 === template }) { templates.append(template) }
        }
        for template in templates {
            let remaining = template.sortedExercises.filter { !removed.contains($0.persistentModelID) }
            for (index, item) in remaining.enumerated() { item.order = index }
        }
        for row in rows { context.delete(row) }
        context.delete(exercise)
        try context.save()
    }

    // MARK: - Allenamenti (nome, orari)

    func renameSession(_ session: WorkoutSession, to name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw WorkoutServiceError.emptySessionName }
        session.name = clean
        try context.save()
    }

    /// Cambia inizio e fine di un allenamento concluso (la fine non può precedere l'inizio).
    func updateSessionTimes(_ session: WorkoutSession, startedAt: Date, endedAt: Date) throws {
        guard !session.isOpen else { throw WorkoutServiceError.sessionStillOpen }
        guard endedAt >= startedAt else { throw WorkoutServiceError.endBeforeStart }
        session.startedAt = startedAt
        session.endedAt = endedAt
        try context.save()
    }

    /// Registra a posteriori un allenamento già fatto: sessione chiusa con un esercizio e una serie completata.
    @discardableResult
    func createPastSession(name: String, startedAt: Date, endedAt: Date, exercise: Exercise, weightKg: Double, reps: Int) throws -> WorkoutSession {
        guard endedAt >= startedAt else { throw WorkoutServiceError.endBeforeStart }
        guard !exercise.isArchived else { throw WorkoutServiceError.exerciseArchived(exercise.name) }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = WorkoutSession(name: clean.isEmpty ? "Allenamento" : clean, startedAt: startedAt, endedAt: endedAt)
        context.insert(session)
        let item = SessionExercise(exercise: exercise, order: 0, restSeconds: exercise.defaultRestSeconds ?? Self.fallbackRestSeconds)
        item.session = session
        context.insert(item)
        let entry = SetEntry(order: 0, weightKg: max(weightKg, 0), reps: max(reps, 0), completedAt: endedAt)
        entry.sessionExercise = item
        context.insert(entry)
        try context.save()
        return session
    }

    // MARK: - Allenamenti conclusi: serie ed esercizi

    /// Aggiunge una serie (già completata) a un esercizio di un allenamento concluso.
    @discardableResult
    func addCompletedSet(to item: SessionExercise, weightKg: Double, reps: Int, type: SetType = .normal) throws -> SetEntry {
        guard let session = item.session, !session.isOpen else { throw WorkoutServiceError.sessionStillOpen }
        let entry = SetEntry(
            order: (item.sortedSets.last?.order ?? -1) + 1,
            weightKg: max(weightKg, 0), reps: max(reps, 0), type: type,
            completedAt: session.endedAt
        )
        entry.sessionExercise = item
        context.insert(entry)
        try context.save()
        return entry
    }

    /// Elimina una serie di un allenamento concluso. Se era l'ultima completata lancia `sessionWouldBeEmpty`
    /// (la UI propone di eliminare l'intero allenamento). Se l'esercizio resta senza serie, viene tolto anch'esso.
    func removeSetFromHistory(_ entry: SetEntry) throws {
        guard let item = entry.sessionExercise, let session = item.session else { return }
        guard !session.isOpen else { throw WorkoutServiceError.sessionStillOpen }
        guard session.completedSetCount - (entry.isCompleted ? 1 : 0) >= 1 else { throw WorkoutServiceError.sessionWouldBeEmpty }
        if item.sets.count == 1 {
            try removeSessionExercise(item)
        } else {
            try removeSet(entry)
        }
    }

    /// Aggiunge un esercizio a un allenamento concluso, con una serie già completata da correggere.
    @discardableResult
    func addExerciseToHistory(_ exercise: Exercise, to session: WorkoutSession, weightKg: Double = 0, reps: Int = 0) throws -> SessionExercise {
        guard !session.isOpen else { throw WorkoutServiceError.sessionStillOpen }
        guard !exercise.isArchived else { throw WorkoutServiceError.exerciseArchived(exercise.name) }
        let item = SessionExercise(
            exercise: exercise,
            order: (session.sortedExercises.last?.order ?? -1) + 1,
            restSeconds: exercise.defaultRestSeconds ?? Self.fallbackRestSeconds
        )
        item.session = session
        context.insert(item)
        let entry = SetEntry(order: 0, weightKg: max(weightKg, 0), reps: max(reps, 0), completedAt: session.endedAt)
        entry.sessionExercise = item
        context.insert(entry)
        try context.save()
        return item
    }

    /// Toglie un esercizio da un allenamento concluso. Se lascerebbe l'allenamento senza serie completate
    /// lancia `sessionWouldBeEmpty`.
    func removeExerciseFromHistory(_ item: SessionExercise) throws {
        guard let session = item.session else { return }
        guard !session.isOpen else { throw WorkoutServiceError.sessionStillOpen }
        guard session.completedSetCount - item.completedSets.count >= 1 else { throw WorkoutServiceError.sessionWouldBeEmpty }
        try removeSessionExercise(item)
    }
}
