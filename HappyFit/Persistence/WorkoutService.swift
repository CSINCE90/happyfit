import Foundation
import SwiftData

/// Errori di business del servizio allenamenti.
enum WorkoutServiceError: LocalizedError, Equatable {
    case sessionAlreadyOpen
    case sessionAlreadyFinished
    case emptyExerciseName
    case duplicateExerciseName(String)
    case exerciseArchived(String)
    case noCompletedSets
    case emptyTemplateName
    case emptySessionName
    case exerciseUsedInSessions(name: String, count: Int)
    case exerciseUsedInTemplates(name: String, templates: [String])
    case endBeforeStart
    case sessionStillOpen
    case sessionWouldBeEmpty

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyOpen:
            return "Esiste già un allenamento in corso: terminalo prima di iniziarne un altro."
        case .sessionAlreadyFinished:
            return "L'allenamento è già concluso."
        case .emptyExerciseName:
            return "Il nome dell'esercizio non può essere vuoto."
        case .duplicateExerciseName(let name):
            return "Esiste già un esercizio chiamato \"\(name)\"."
        case .exerciseArchived(let name):
            return "L'esercizio \"\(name)\" è archiviato."
        case .noCompletedSets:
            return "Nessuna serie completata: non c'è nulla da salvare. Puoi scartare l'allenamento."
        case .emptyTemplateName:
            return "Il nome della scheda non può essere vuoto."
        case .emptySessionName:
            return "Il nome dell'allenamento non può essere vuoto."
        case .exerciseUsedInSessions(let name, let count):
            return "\"\(name)\" compare in \(count) \(count == 1 ? "allenamento" : "allenamenti"): eliminarlo falserebbe lo storico. Puoi archiviarlo."
        case .exerciseUsedInTemplates(let name, let templates):
            return "\"\(name)\" è usato nelle schede: \(templates.joined(separator: ", "))."
        case .endBeforeStart:
            return "La fine dell'allenamento non può precedere l'inizio."
        case .sessionStillOpen:
            return "L'allenamento è ancora in corso."
        case .sessionWouldBeEmpty:
            return "Un allenamento concluso deve avere almeno una serie completata."
        }
    }
}

/// Logica degli allenamenti sopra SwiftData, senza UI.
@MainActor
struct WorkoutService {
    /// Recupero usato quando né l'esercizio né l'utente ne specificano uno.
    nonisolated static let fallbackRestSeconds = 90

    let context: ModelContext

    // MARK: - Catalogo

    /// Esercizi attivi (esclusi gli archiviati), ordinati per nome.
    func catalog() throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    @discardableResult
    func createExercise(name: String, muscleGroup: MuscleGroup? = nil, defaultRestSeconds: Int? = nil) throws -> Exercise {
        let clean = try validatedName(name, excluding: nil)
        let exercise = Exercise(name: clean, muscleGroup: muscleGroup, defaultRestSeconds: defaultRestSeconds)
        context.insert(exercise)
        try context.save()
        return exercise
    }

    func renameExercise(_ exercise: Exercise, to name: String) throws {
        exercise.name = try validatedName(name, excluding: exercise)
        try context.save()
    }

    func setMuscleGroup(_ exercise: Exercise, _ group: MuscleGroup?) throws {
        exercise.muscleGroup = group
        try context.save()
    }

    /// Recupero proposto quando l'esercizio entra in una scheda o in una sessione (nil = usa l'impostazione globale).
    func setDefaultRest(_ exercise: Exercise, seconds: Int?) throws {
        exercise.defaultRestSeconds = seconds.map { max($0, 0) }
        try context.save()
    }

    /// Niente cancellazione fisica: l'esercizio sparisce dal catalogo ma resta nello storico.
    func archiveExercise(_ exercise: Exercise) throws {
        exercise.isArchived = true
        try context.save()
    }

    func unarchiveExercise(_ exercise: Exercise) throws {
        exercise.isArchived = false
        try context.save()
    }

    /// Controlla il nome (trim, non vuoto, univoco senza distinguere maiuscole/minuscole, anche tra gli archiviati).
    private func validatedName(_ name: String, excluding other: Exercise?) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw WorkoutServiceError.emptyExerciseName }
        let all = try context.fetch(FetchDescriptor<Exercise>())
        if all.contains(where: { $0 !== other && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            throw WorkoutServiceError.duplicateExerciseName(clean)
        }
        return clean
    }

    // MARK: - Template

    /// Schede ordinate per `order`.
    func templates() throws -> [WorkoutTemplate] {
        try context.fetch(FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.order)]))
    }

    @discardableResult
    func createTemplate(name: String, exercises: [(exercise: Exercise, sets: Int, reps: Int, restSeconds: Int)] = []) throws -> WorkoutTemplate {
        let clean = try validatedTemplateName(name)
        let order = (try templates().last?.order ?? -1) + 1
        let template = WorkoutTemplate(name: clean, order: order)
        context.insert(template)
        for (index, item) in exercises.enumerated() {
            let row = TemplateExercise(exercise: item.exercise, order: index, targetSets: item.sets, targetReps: item.reps, restSeconds: item.restSeconds)
            row.template = template
            context.insert(row)
        }
        try context.save()
        return template
    }

    func renameTemplate(_ template: WorkoutTemplate, to name: String) throws {
        template.name = try validatedTemplateName(name)
        try context.save()
    }

    /// Copia la scheda (nome + " (copia)") in fondo alla lista.
    @discardableResult
    func duplicateTemplate(_ template: WorkoutTemplate) throws -> WorkoutTemplate {
        let copy = try createTemplate(
            name: template.name + " (copia)",
            exercises: template.sortedExercises.compactMap { row in
                row.exercise.map { ($0, row.targetSets, row.targetReps, row.restSeconds) }
            }
        )
        return copy
    }

    func deleteTemplate(_ template: WorkoutTemplate) throws {
        let remaining = try templates().filter { $0 !== template }
        context.delete(template)
        for (index, item) in remaining.enumerated() { item.order = index }
        try context.save()
    }

    func reorderTemplates(_ ordered: [WorkoutTemplate]) throws {
        for (index, item) in ordered.enumerated() { item.order = index }
        try context.save()
    }

    @discardableResult
    func addExercise(_ exercise: Exercise, to template: WorkoutTemplate, sets: Int = 3, reps: Int = 10, restSeconds: Int? = nil) throws -> TemplateExercise {
        guard !exercise.isArchived else { throw WorkoutServiceError.exerciseArchived(exercise.name) }
        let row = TemplateExercise(
            exercise: exercise,
            order: (template.sortedExercises.last?.order ?? -1) + 1,
            targetSets: max(sets, 1),
            targetReps: max(reps, 1),
            restSeconds: restSeconds ?? exercise.defaultRestSeconds ?? Self.fallbackRestSeconds
        )
        row.template = template
        context.insert(row)
        try context.save()
        return row
    }

    func removeTemplateExercise(_ row: TemplateExercise) throws {
        let remaining = (row.template?.sortedExercises ?? []).filter { $0 !== row }
        context.delete(row)
        for (index, item) in remaining.enumerated() { item.order = index }
        try context.save()
    }

    func reorderTemplateExercises(_ ordered: [TemplateExercise]) throws {
        for (index, item) in ordered.enumerated() { item.order = index }
        try context.save()
    }

    func updateTemplateExercise(_ row: TemplateExercise, sets: Int? = nil, reps: Int? = nil, restSeconds: Int? = nil) throws {
        if let sets { row.targetSets = max(sets, 1) }
        if let reps { row.targetReps = max(reps, 1) }
        if let restSeconds { row.restSeconds = max(restSeconds, 0) }
        try context.save()
    }

    private func validatedTemplateName(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw WorkoutServiceError.emptyTemplateName }
        return clean
    }

    // MARK: - Sessioni

    /// Sessione aperta, se c'è.
    func openSession() throws -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Sessione libera, senza esercizi: si aggiungono durante l'allenamento.
    @discardableResult
    func startEmptySession(name: String, at date: Date = Date()) throws -> WorkoutSession {
        guard try openSession() == nil else { throw WorkoutServiceError.sessionAlreadyOpen }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = WorkoutSession(name: clean.isEmpty ? "Allenamento libero" : clean, startedAt: date)
        context.insert(session)
        try context.save()
        return session
    }

    /// Crea una sessione da un template, precompilando dall'ultimo allenamento di ogni esercizio.
    @discardableResult
    func startSession(from template: WorkoutTemplate, at date: Date = Date()) throws -> WorkoutSession {
        guard try openSession() == nil else { throw WorkoutServiceError.sessionAlreadyOpen }

        let session = WorkoutSession(name: template.name, startedAt: date, template: template)
        context.insert(session)

        for row in template.sortedExercises {
            guard let exercise = row.exercise else { continue }
            let sessionExercise = SessionExercise(exercise: exercise, order: session.exercises.count, restSeconds: row.restSeconds)
            sessionExercise.session = session
            context.insert(sessionExercise)

            if let previous = try lastPerformance(of: exercise, before: date) {
                // Valori dell'ultima volta, ma da completare di nuovo.
                for (index, old) in previous.enumerated() {
                    appendSet(to: sessionExercise, order: index, weightKg: old.weightKg, reps: old.reps, type: old.type)
                }
            } else {
                // Nessuno storico: serie vuote con le ripetizioni target.
                for index in 0..<max(row.targetSets, 0) {
                    appendSet(to: sessionExercise, order: index, weightKg: 0, reps: row.targetReps, type: .normal)
                }
            }
        }
        try context.save()
        return session
    }

    /// Ultima volta in cui l'esercizio è stato fatto: sessione chiusa con almeno una serie completata.
    /// Ritorna solo le serie completate, in ordine. `before` limita la ricerca alle sessioni iniziate prima.
    func lastPerformance(of exercise: Exercise, before: Date? = nil) throws -> [SetEntry]? {
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil })
        let closed = try context.fetch(descriptor).sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
        for session in closed {
            if let before, session.startedAt >= before { continue }
            for item in session.sortedExercises where item.exercise?.id == exercise.id {
                let completed = item.completedSets
                if !completed.isEmpty { return completed }
            }
        }
        return nil
    }

    @discardableResult
    func addSet(to sessionExercise: SessionExercise, weightKg: Double? = nil, reps: Int? = nil, type: SetType = .normal) throws -> SetEntry {
        let last = sessionExercise.sortedSets.last
        let entry = appendSet(
            to: sessionExercise,
            order: (last?.order ?? -1) + 1,
            weightKg: weightKg ?? last?.weightKg ?? 0,
            reps: reps ?? last?.reps ?? 0,
            type: type
        )
        try context.save()
        return entry
    }

    /// Rimuove la serie e riordina le restanti.
    func removeSet(_ entry: SetEntry) throws {
        let parent = entry.sessionExercise
        context.delete(entry)
        if let parent {
            let remaining = parent.sortedSets.filter { $0 !== entry }
            for (index, item) in remaining.enumerated() { item.order = index }
        }
        try context.save()
    }

    /// Segna la serie come completata, con eventuali valori aggiornati.
    func completeSet(_ entry: SetEntry, weightKg: Double? = nil, reps: Int? = nil, at date: Date = Date()) throws {
        if let weightKg { entry.weightKg = weightKg }
        if let reps { entry.reps = reps }
        entry.completedAt = date
        try context.save()
    }

    func uncompleteSet(_ entry: SetEntry) throws {
        entry.completedAt = nil
        try context.save()
    }

    /// Aggiunge un esercizio libero a una sessione in corso (precompilato se c'è storico, altrimenti una serie vuota).
    @discardableResult
    func addExercise(_ exercise: Exercise, to session: WorkoutSession, restSeconds: Int? = nil) throws -> SessionExercise {
        guard session.isOpen else { throw WorkoutServiceError.sessionAlreadyFinished }
        guard !exercise.isArchived else { throw WorkoutServiceError.exerciseArchived(exercise.name) }

        let last = session.sortedExercises.last
        let sessionExercise = SessionExercise(
            exercise: exercise,
            order: (last?.order ?? -1) + 1,
            restSeconds: restSeconds ?? exercise.defaultRestSeconds ?? Self.fallbackRestSeconds
        )
        sessionExercise.session = session
        context.insert(sessionExercise)

        if let previous = try lastPerformance(of: exercise, before: session.startedAt) {
            for (index, old) in previous.enumerated() {
                appendSet(to: sessionExercise, order: index, weightKg: old.weightKg, reps: old.reps, type: old.type)
            }
        } else {
            appendSet(to: sessionExercise, order: 0, weightKg: 0, reps: 0, type: .normal)
        }
        try context.save()
        return sessionExercise
    }

    /// Chiude la sessione tenendo solo le serie completate: elimina le incomplete e gli esercizi rimasti senza serie.
    /// Se non c'è nessuna serie completata lancia `noCompletedSets` e non cambia nulla (usare `discard`).
    func finish(_ session: WorkoutSession, at date: Date = Date()) throws {
        guard session.isOpen else { throw WorkoutServiceError.sessionAlreadyFinished }
        guard session.completedSetCount > 0 else { throw WorkoutServiceError.noCompletedSets }

        let kept = session.sortedExercises.filter { !$0.completedSets.isEmpty }
        for item in session.sortedExercises where item.completedSets.isEmpty { context.delete(item) }
        for (index, item) in kept.enumerated() {
            item.order = index
            let done = item.completedSets
            for entry in item.sortedSets where !entry.isCompleted { context.delete(entry) }
            for (setIndex, entry) in done.enumerated() { entry.order = setIndex }
        }
        session.endedAt = date
        try context.save()
    }

    /// Scarta una sessione ancora aperta (elimina anche serie ed esercizi di sessione).
    func discard(_ session: WorkoutSession) throws {
        guard session.isOpen else { throw WorkoutServiceError.sessionAlreadyFinished }
        context.delete(session)
        try context.save()
    }

    /// Modifica peso, ripetizioni o tipo di una serie (anche di una sessione chiusa).
    func updateSet(_ entry: SetEntry, weightKg: Double? = nil, reps: Int? = nil, type: SetType? = nil) throws {
        if let weightKg { entry.weightKg = max(weightKg, 0) }
        if let reps { entry.reps = max(reps, 0) }
        if let type { entry.type = type }
        try context.save()
    }

    func removeSessionExercise(_ item: SessionExercise) throws {
        let remaining = (item.session?.sortedExercises ?? []).filter { $0 !== item }
        context.delete(item)
        for (index, other) in remaining.enumerated() { other.order = index }
        try context.save()
    }

    func reorderSessionExercises(_ ordered: [SessionExercise]) throws {
        for (index, item) in ordered.enumerated() { item.order = index }
        try context.save()
    }

    /// Cambia il recupero di un esercizio solo per questa sessione.
    func updateRest(_ item: SessionExercise, seconds: Int) throws {
        item.restSeconds = max(seconds, 0)
        try context.save()
    }

    func deleteSession(_ session: WorkoutSession) throws {
        context.delete(session)
        try context.save()
    }

    // MARK: - DTO

    /// DTO per il Watch, con le serie completate dell'ultima volta per ogni esercizio.
    func makeDTO(for session: WorkoutSession) throws -> WorkoutSessionDTO {
        var previous: [UUID: [SetEntryDTO]] = [:]
        for item in session.sortedExercises {
            guard let exercise = item.exercise else { continue }
            if let sets = try lastPerformance(of: exercise, before: session.startedAt) {
                previous[exercise.id] = sets.map { $0.toDTO() }
            }
        }
        return WorkoutSessionDTO(
            id: session.id,
            name: session.name,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            exercises: session.sortedExercises.compactMap { $0.toDTO() },
            previousSets: previous
        )
    }

    /// Importa (o aggiorna, se l'id esiste già) una sessione ricevuta dal Watch.
    /// L'esercizio si risolve per id, poi per nome (senza maiuscole/minuscole), altrimenti viene creato.
    @discardableResult
    func importSession(_ dto: WorkoutSessionDTO) throws -> WorkoutSession {
        let id = dto.id
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1

        let session: WorkoutSession
        if let existing = try context.fetch(descriptor).first {
            session = existing
            session.name = dto.name
            session.startedAt = dto.startedAt
            session.endedAt = dto.endedAt
            for old in existing.exercises { context.delete(old) }
        } else {
            session = WorkoutSession(id: dto.id, name: dto.name, startedAt: dto.startedAt, endedAt: dto.endedAt)
            context.insert(session)
        }

        for item in dto.exercises.sorted(by: { $0.order < $1.order }) {
            let sessionExercise = SessionExercise(id: item.id, exercise: try resolveExercise(item.exercise), order: item.order, restSeconds: item.restSeconds)
            sessionExercise.session = session
            context.insert(sessionExercise)
            for set in item.sets {
                let entry = SetEntry(dto: set)
                entry.sessionExercise = sessionExercise
                context.insert(entry)
            }
        }
        try context.save()
        return session
    }

    private func resolveExercise(_ dto: ExerciseDTO) throws -> Exercise {
        let all = try context.fetch(FetchDescriptor<Exercise>())
        if let byID = all.first(where: { $0.id == dto.id }) { return byID }
        if let byName = all.first(where: { $0.name.caseInsensitiveCompare(dto.name) == .orderedSame }) { return byName }
        let created = Exercise(id: dto.id, name: dto.name)
        context.insert(created)
        return created
    }

    // MARK: - Interni

    @discardableResult
    private func appendSet(to sessionExercise: SessionExercise, order: Int, weightKg: Double, reps: Int, type: SetType) -> SetEntry {
        let entry = SetEntry(order: order, weightKg: weightKg, reps: reps, type: type)
        entry.sessionExercise = sessionExercise
        context.insert(entry)
        return entry
    }
}
