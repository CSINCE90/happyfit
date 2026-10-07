import XCTest
import SwiftData
@testable import HappyFit

/// Test della logica allenamenti con SwiftData in memoria.
@MainActor
final class WorkoutServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: WorkoutService!
    private var panca: Exercise!
    private var squat: Exercise!
    private var template: WorkoutTemplate!

    private let day1 = Date(timeIntervalSince1970: 1_700_000_000)
    private var day2: Date { day1.addingTimeInterval(86_400) }
    private var day3: Date { day1.addingTimeInterval(2 * 86_400) }

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = ModelContext(container)
        service = WorkoutService(context: context)
        panca = try service.createExercise(name: "Panca piana", muscleGroup: .petto)
        squat = try service.createExercise(name: "Squat", muscleGroup: .gambe)
        template = try service.createTemplate(name: "Push", exercises: [
            (panca, 3, 8, 120),
            (squat, 2, 5, 180)
        ])
    }

    /// Fa e chiude un allenamento completando le prime `completed` serie di ogni esercizio.
    @discardableResult
    private func runSession(at start: Date, completing completed: Int, weights: [Double] = [], reps: [Int] = []) throws -> WorkoutSession {
        let session = try service.startSession(from: template, at: start)
        for item in session.sortedExercises {
            for (index, set) in item.sortedSets.enumerated() where index < completed {
                try service.completeSet(
                    set,
                    weightKg: index < weights.count ? weights[index] : nil,
                    reps: index < reps.count ? reps[index] : nil,
                    at: start.addingTimeInterval(60)
                )
            }
        }
        try service.finish(session, at: start.addingTimeInterval(3600))
        return session
    }

    // MARK: - Creazione da template

    func testStartSessionWithoutHistoryCreatesEmptySets() throws {
        let session = try service.startSession(from: template, at: day1)
        XCTAssertEqual(session.name, "Push")
        XCTAssertTrue(session.isOpen)
        XCTAssertTrue(session.template === template)

        let items = session.sortedExercises
        XCTAssertEqual(items.map { $0.exercise?.name }, ["Panca piana", "Squat"])
        XCTAssertEqual(items[0].sortedSets.count, 3)
        XCTAssertEqual(items[1].sortedSets.count, 2)
        for set in items.flatMap({ $0.sortedSets }) {
            XCTAssertEqual(set.weightKg, 0)
            XCTAssertNil(set.completedAt)
        }
        XCTAssertEqual(items[0].sortedSets.map(\.reps), [8, 8, 8])
        XCTAssertEqual(items[1].sortedSets.map(\.order), [0, 1])
    }

    func testStartSessionPrefillsFromLastCompletedSets() throws {
        try runSession(at: day1, completing: 2, weights: [50, 60], reps: [8, 6])

        let session = try service.startSession(from: template, at: day2)
        let sets = session.sortedExercises[0].sortedSets
        // Solo le 2 serie completate, non le 3 del template.
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.map(\.weightKg), [50, 60])
        XCTAssertEqual(sets.map(\.reps), [8, 6])
        XCTAssertTrue(sets.allSatisfy { $0.completedAt == nil })
    }

    func testPrefillSkipsSessionsWhereExerciseHasNoCompletedSets() throws {
        try runSession(at: day1, completing: 2, weights: [50, 60], reps: [8, 6])
        // Giorno 2: solo la panca ha serie completate, lo squat viene tolto alla chiusura.
        let second = try service.startSession(from: template, at: day2)
        try service.completeSet(second.sortedExercises[0].sortedSets[0], weightKg: 52, reps: 8, at: day2)
        try service.finish(second, at: day2.addingTimeInterval(3600))

        let third = try service.startSession(from: template, at: day3)
        XCTAssertEqual(third.sortedExercises[0].sortedSets.map(\.weightKg), [52])
        // Per lo squat si cerca più indietro, fino al giorno 1.
        XCTAssertEqual(third.sortedExercises[1].sortedSets.count, 2)
    }

    func testLastPerformanceIgnoresOpenSessions() throws {
        let open = try service.startSession(from: template, at: day1)
        try service.completeSet(open.sortedExercises[0].sortedSets[0], weightKg: 40, reps: 10)
        XCTAssertNil(try service.lastPerformance(of: panca))
    }

    // MARK: - Serie

    func testAddCompleteAndRemoveSet() throws {
        let session = try service.startSession(from: template, at: day1)
        let item = session.sortedExercises[0]

        let added = try service.addSet(to: item, weightKg: 70, reps: 5)
        XCTAssertEqual(item.sortedSets.count, 4)
        XCTAssertEqual(added.order, 3)

        try service.completeSet(added, at: day1)
        XCTAssertTrue(added.isCompleted)
        try service.uncompleteSet(added)
        XCTAssertFalse(added.isCompleted)

        // Rimuovendo la prima serie, le altre si riordinano.
        try service.removeSet(item.sortedSets[0])
        XCTAssertEqual(item.sortedSets.count, 3)
        XCTAssertEqual(item.sortedSets.map(\.order), [0, 1, 2])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 5)
    }

    func testAddFreeExerciseAndFinish() throws {
        let session = try service.startSession(from: template, at: day1)
        let curl = try service.createExercise(name: "Curl", muscleGroup: .braccia)

        let item = try service.addExercise(curl, to: session)
        XCTAssertEqual(item.order, 2)
        XCTAssertEqual(item.sortedSets.count, 1)
        XCTAssertEqual(item.restSeconds, 90)
        try service.completeSet(item.sortedSets[0], weightKg: 10, reps: 12)

        try service.finish(session, at: day1.addingTimeInterval(100))
        XCTAssertFalse(session.isOpen)
        XCTAssertThrowsError(try service.finish(session)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .sessionAlreadyFinished)
        }
        XCTAssertThrowsError(try service.addExercise(curl, to: session)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .sessionAlreadyFinished)
        }
    }

    func testDeleteSessionRemovesSetsButKeepsCatalog() throws {
        let session = try runSession(at: day1, completing: 2)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<SetEntry>()), 0)

        try service.deleteSession(session)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()), 1)
    }

    // MARK: - Sessione aperta

    func testOpenSessionAndNoSecondSession() throws {
        XCTAssertNil(try service.openSession())

        let session = try service.startSession(from: template, at: day1)
        XCTAssertTrue(try service.openSession() === session)

        XCTAssertThrowsError(try service.startSession(from: template, at: day2)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .sessionAlreadyOpen)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)

        try service.completeSet(session.sortedExercises[0].sortedSets[0], weightKg: 10, reps: 5)
        try service.finish(session, at: day1.addingTimeInterval(10))
        XCTAssertNil(try service.openSession())
        XCTAssertNoThrow(try service.startSession(from: template, at: day2))
    }

    // MARK: - Chiusura e scarto

    func testFinishKeepsOnlyCompletedSetsAndDropsEmptyExercises() throws {
        let session = try service.startSession(from: template, at: day1)
        let panca = session.sortedExercises[0]
        // Completo solo la 1ª e la 3ª serie della panca; lo squat resta senza serie completate.
        try service.completeSet(panca.sortedSets[0], weightKg: 50, reps: 8)
        try service.completeSet(panca.sortedSets[2], weightKg: 60, reps: 6)

        try service.finish(session, at: day1.addingTimeInterval(3600))

        XCTAssertFalse(session.isOpen)
        XCTAssertEqual(session.sortedExercises.count, 1)
        XCTAssertEqual(session.sortedExercises[0].exercise?.name, "Panca piana")
        XCTAssertEqual(session.sortedExercises[0].sortedSets.map(\.weightKg), [50, 60])
        XCTAssertEqual(session.sortedExercises[0].sortedSets.map(\.order), [0, 1])
        XCTAssertEqual(session.incompleteSetCount, 0)
        // Nel database non restano serie incomplete né esercizi vuoti.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 1)
    }

    func testFinishWithoutCompletedSetsThrowsAndChangesNothing() throws {
        let session = try service.startSession(from: template, at: day1)
        XCTAssertThrowsError(try service.finish(session)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .noCompletedSets)
        }
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(session.sortedExercises.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 5)
    }

    func testDiscardDeletesOpenSession() throws {
        let session = try service.startSession(from: template, at: day1)
        try service.discard(session)
        XCTAssertNil(try service.openSession())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)

        let closed = try runSession(at: day1, completing: 1)
        XCTAssertThrowsError(try service.discard(closed)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .sessionAlreadyFinished)
        }
    }

    func testStartEmptySession() throws {
        let session = try service.startEmptySession(name: "  ", at: day1)
        XCTAssertEqual(session.name, "Allenamento libero")
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertThrowsError(try service.startEmptySession(name: "Altro")) {
            XCTAssertEqual($0 as? WorkoutServiceError, .sessionAlreadyOpen)
        }
    }

    func testSessionRestComesFromTemplateAndIsEditable() throws {
        let session = try service.startSession(from: template, at: day1)
        XCTAssertEqual(session.sortedExercises.map(\.restSeconds), [120, 180])
        try service.updateRest(session.sortedExercises[0], seconds: 45)
        XCTAssertEqual(session.sortedExercises[0].restSeconds, 45)
        // Il template non cambia.
        XCTAssertEqual(template.sortedExercises[0].restSeconds, 120)
    }

    func testUpdateSetClampsAndRemoveSessionExerciseReorders() throws {
        let session = try service.startSession(from: template, at: day1)
        let set = session.sortedExercises[0].sortedSets[0]
        try service.updateSet(set, weightKg: -5, reps: -1, type: .failure)
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertEqual(set.reps, 0)
        XCTAssertEqual(set.type, .failure)

        try service.removeSessionExercise(session.sortedExercises[0])
        XCTAssertEqual(session.sortedExercises.map(\.order), [0])
        XCTAssertEqual(session.sortedExercises[0].exercise?.name, "Squat")
    }

    // MARK: - Schede

    func testTemplateCrud() throws {
        XCTAssertThrowsError(try service.createTemplate(name: "  ")) {
            XCTAssertEqual($0 as? WorkoutServiceError, .emptyTemplateName)
        }
        let pull = try service.createTemplate(name: "Pull")
        XCTAssertEqual(pull.order, 1)
        try service.renameTemplate(pull, to: "Pull A")
        XCTAssertEqual(pull.name, "Pull A")

        let copy = try service.duplicateTemplate(template)
        XCTAssertEqual(copy.name, "Push (copia)")
        XCTAssertEqual(copy.sortedExercises.map(\.targetSets), [3, 2])
        XCTAssertEqual(copy.sortedExercises.map { $0.exercise?.name }, ["Panca piana", "Squat"])
        XCTAssertEqual(copy.order, 2)

        try service.reorderTemplates([copy, pull, template])
        XCTAssertEqual(try service.templates().map(\.name), ["Push (copia)", "Pull A", "Push"])

        try service.deleteTemplate(pull)
        XCTAssertEqual(try service.templates().map(\.order), [0, 1])
        // Cancellare una scheda non tocca esercizi né sessioni già fatte.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
    }

    func testTemplateExerciseEditing() throws {
        let curl = try service.createExercise(name: "Curl", defaultRestSeconds: 60)
        let row = try service.addExercise(curl, to: template)
        XCTAssertEqual(row.order, 2)
        XCTAssertEqual(row.restSeconds, 60)

        try service.updateTemplateExercise(row, sets: 0, reps: 12, restSeconds: -3)
        XCTAssertEqual(row.targetSets, 1)
        XCTAssertEqual(row.targetReps, 12)
        XCTAssertEqual(row.restSeconds, 0)

        try service.reorderTemplateExercises([row] + template.sortedExercises.filter { $0 !== row })
        XCTAssertEqual(template.sortedExercises.first?.exercise?.name, "Curl")

        try service.removeTemplateExercise(template.sortedExercises[0])
        XCTAssertEqual(template.sortedExercises.map(\.order), [0, 1])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 3)
    }

    func testSetMuscleGroupAndDefaultRest() throws {
        try service.setMuscleGroup(squat, .core)
        try service.setDefaultRest(squat, seconds: 150)
        XCTAssertEqual(squat.muscleGroup, .core)
        XCTAssertEqual(squat.defaultRestSeconds, 150)
        try service.setDefaultRest(squat, seconds: nil)
        XCTAssertNil(squat.defaultRestSeconds)
    }

    // MARK: - Catalogo

    func testExerciseNameUniquenessIsCaseInsensitive() throws {
        XCTAssertThrowsError(try service.createExercise(name: "  panca PIANA ")) {
            XCTAssertEqual($0 as? WorkoutServiceError, .duplicateExerciseName("panca PIANA"))
        }
        XCTAssertThrowsError(try service.renameExercise(squat, to: "PANCA piana")) {
            XCTAssertEqual($0 as? WorkoutServiceError, .duplicateExerciseName("PANCA piana"))
        }
        XCTAssertThrowsError(try service.createExercise(name: "   ")) {
            XCTAssertEqual($0 as? WorkoutServiceError, .emptyExerciseName)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
        // Rinominare con lo stesso nome (cambiando solo le maiuscole) è lecito.
        XCTAssertNoThrow(try service.renameExercise(squat, to: "SQUAT"))
    }

    func testArchivedExerciseHiddenFromCatalogButKeptInHistory() throws {
        let session = try runSession(at: day1, completing: 1)
        try service.archiveExercise(squat)

        XCTAssertEqual(try service.catalog().map(\.name), ["Panca piana"])
        XCTAssertEqual(session.sortedExercises.compactMap { $0.exercise?.name }, ["Panca piana", "Squat"])
        // Anche archiviato, il nome resta occupato.
        XCTAssertThrowsError(try service.createExercise(name: "squat"))

        let open = try service.startSession(from: template, at: day2)
        XCTAssertThrowsError(try service.addExercise(squat, to: open)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .exerciseArchived("Squat"))
        }
        try service.unarchiveExercise(squat)
        XCTAssertEqual(try service.catalog().count, 2)
    }

    func testSeedCatalogLoadsOnlyOnce() throws {
        let fresh = ModelContext(try PersistenceController.makeContainer(inMemory: true))
        XCTAssertTrue(try ExerciseCatalog.seedIfNeeded(in: fresh))
        let count = try fresh.fetchCount(FetchDescriptor<Exercise>())
        XCTAssertEqual(count, ExerciseCatalog.initialExercises.count)
        XCTAssertGreaterThanOrEqual(count, 25)
        XCTAssertFalse(try ExerciseCatalog.seedIfNeeded(in: fresh))
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Exercise>()), count)
        // Nomi tutti diversi senza distinguere maiuscole/minuscole.
        XCTAssertEqual(Set(ExerciseCatalog.initialExercises.map { $0.name.lowercased() }).count, count)
    }

    // MARK: - DTO

    func testRoundTripModelToDTOToJSONToDTO() throws {
        try runSession(at: day1, completing: 2, weights: [50, 60], reps: [8, 6])
        let session = try service.startSession(from: template, at: day2)
        try service.completeSet(session.sortedExercises[0].sortedSets[0], weightKg: 55, reps: 8, at: day2)

        let dto = try service.makeDTO(for: session)
        XCTAssertEqual(dto.exercises.count, 2)
        // previousSets: solo serie completate della volta precedente.
        XCTAssertEqual(dto.previousSets[panca.id]?.map(\.weightKg), [50, 60])
        XCTAssertEqual(dto.previousSets[squat.id]?.count, 2)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutSessionDTO.self, from: encoder.encode(dto))
        XCTAssertEqual(decoded, dto)

        // Reimport in un contesto vuoto: il DTO rigenerato coincide con l'originale.
        let otherContext = ModelContext(try PersistenceController.makeContainer(inMemory: true))
        let otherService = WorkoutService(context: otherContext)
        let imported = try otherService.importSession(decoded)
        XCTAssertEqual(imported.id, session.id)
        let again = try otherService.makeDTO(for: imported)
        XCTAssertEqual(again.exercises, dto.exercises)
        XCTAssertEqual(again.name, dto.name)
        XCTAssertEqual(again.startedAt, dto.startedAt)
        XCTAssertEqual(again.endedAt, dto.endedAt)

        // Reimportare lo stesso id aggiorna senza duplicare.
        try otherService.importSession(decoded)
        XCTAssertEqual(try otherContext.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try otherContext.fetchCount(FetchDescriptor<SetEntry>()), dto.exercises.flatMap(\.sets).count)
    }
}
