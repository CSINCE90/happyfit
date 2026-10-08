import XCTest
import SwiftData
@testable import HappyFit

/// Test del CRUD completo: eliminazione sicura di schede ed esercizi, modifica dello storico.
@MainActor
final class EditingServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: WorkoutService!
    private var panca: Exercise!
    private var squat: Exercise!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = ModelContext(container)
        service = WorkoutService(context: context)
        panca = try service.createExercise(name: "Panca")
        squat = try service.createExercise(name: "Squat")
    }

    /// Sessione chiusa con panca (3 serie completate) e squat (2 serie completate).
    private func closedSession(at start: Date? = nil) throws -> WorkoutSession {
        let template = try service.createTemplate(name: "T\(UUID().uuidString.prefix(4))", exercises: [(panca, 3, 8, 60), (squat, 2, 5, 60)])
        let session = try service.startSession(from: template, at: start ?? t0)
        for item in session.sortedExercises {
            for entry in item.sortedSets { try service.completeSet(entry, weightKg: 50, reps: 8, at: session.startedAt) }
        }
        try service.finish(session, at: session.startedAt.addingTimeInterval(3_600))
        return session
    }

    // MARK: - Schede

    func testRemoveTemplateDetachesSessionsAndKeepsHistory() throws {
        let session = try closedSession()
        let templateName = try service.templates().first!.name
        XCTAssertEqual(templateName.prefix(1), "T")
        let template = try service.templates().first!

        try service.removeTemplate(template)

        XCTAssertTrue(try service.templates().isEmpty)
        // In un contesto nuovo nessuna sessione punta più a una scheda inesistente.
        let fresh = ModelContext(container)
        let sessions = try fresh.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0].template)
        XCTAssertEqual(sessions[0].completedSetCount, session.completedSetCount)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
    }

    func testRemoveTemplateUsedByOpenSession() throws {
        let template = try service.createTemplate(name: "Aperta", exercises: [(panca, 2, 8, 60)])
        let open = try service.startSession(from: template)
        try service.removeTemplate(template)
        XCTAssertEqual(try service.openSession()?.id, open.id)
        XCTAssertEqual(open.sortedExercises.count, 1)
        XCTAssertNil(ModelContext(container).fetchSafely(WorkoutSession.self).first?.template)
    }

    // MARK: - Catalogo

    func testDeleteUnusedExercise() throws {
        let curl = try service.createExercise(name: "Curl")
        XCTAssertTrue(try service.exerciseUsage(curl).isUnused)
        try service.deleteExercise(curl)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
    }

    func testExerciseUsedInHistoryCannotBeDeleted() throws {
        _ = try closedSession()
        let usage = try service.exerciseUsage(panca)
        XCTAssertEqual(usage.sessionCount, 1)
        XCTAssertThrowsError(try service.deleteExercise(panca)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .exerciseUsedInSessions(name: "Panca", count: 1))
        }
        // Nemmeno forzando la rimozione dalle schede.
        XCTAssertThrowsError(try service.deleteExercise(panca, removingFromTemplates: true))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
        // L'alternativa è archiviare.
        try service.archiveExercise(panca)
        XCTAssertTrue(panca.isArchived)
    }

    func testExerciseOnlyInTemplatesNeedsConfirmationThenIsRemovedEverywhere() throws {
        let a = try service.createTemplate(name: "A", exercises: [(panca, 3, 8, 60), (squat, 3, 8, 60)])
        let b = try service.createTemplate(name: "B", exercises: [(squat, 3, 8, 60), (panca, 3, 8, 60)])
        let usage = try service.exerciseUsage(panca)
        XCTAssertEqual(usage, ExerciseUsage(sessionCount: 0, templateNames: ["A", "B"]))
        XCTAssertThrowsError(try service.deleteExercise(panca)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .exerciseUsedInTemplates(name: "Panca", templates: ["A", "B"]))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)

        try service.deleteExercise(panca, removingFromTemplates: true)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(a.sortedExercises.map { $0.exercise?.name }, ["Squat"])
        XCTAssertEqual(b.sortedExercises.map { $0.exercise?.name }, ["Squat"])
        XCTAssertEqual(a.sortedExercises.map(\.order), [0])
        XCTAssertEqual(b.sortedExercises.map(\.order), [0])
    }

    func testExerciseInOpenSessionCannotBeDeleted() throws {
        let template = try service.createTemplate(name: "T", exercises: [(panca, 3, 8, 60)])
        _ = try service.startSession(from: template)
        XCTAssertThrowsError(try service.deleteExercise(panca)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .exerciseUsedInSessions(name: "Panca", count: 1))
        }
    }

    // MARK: - Allenamenti: nome e orari

    func testRenameSessionAndTimes() throws {
        let session = try closedSession()
        try service.renameSession(session, to: "  Spinta pesante ")
        XCTAssertEqual(session.name, "Spinta pesante")
        XCTAssertThrowsError(try service.renameSession(session, to: " ")) {
            XCTAssertEqual($0 as? WorkoutServiceError, .emptySessionName)
        }

        let newStart = t0.addingTimeInterval(-7_200)
        try service.updateSessionTimes(session, startedAt: newStart, endedAt: newStart.addingTimeInterval(1_800))
        XCTAssertEqual(session.startedAt, newStart)
        XCTAssertEqual(session.endedAt, newStart.addingTimeInterval(1_800))

        XCTAssertThrowsError(try service.updateSessionTimes(session, startedAt: t0, endedAt: t0.addingTimeInterval(-1))) {
            XCTAssertEqual($0 as? WorkoutServiceError, .endBeforeStart)
        }
        XCTAssertEqual(session.startedAt, newStart, "in caso di errore non cambia nulla")

        let template = try service.createTemplate(name: "X", exercises: [(panca, 1, 1, 0)])
        let open = try service.startSession(from: template, at: t0.addingTimeInterval(99_999))
        XCTAssertThrowsError(try service.updateSessionTimes(open, startedAt: t0, endedAt: t0.addingTimeInterval(5))) {
            XCTAssertEqual($0 as? WorkoutServiceError, .sessionStillOpen)
        }
    }

    // MARK: - Allenamenti conclusi: serie ed esercizi

    func testAddAndRemoveSetsInHistory() throws {
        let session = try closedSession()
        let item = session.sortedExercises[0]
        let added = try service.addCompletedSet(to: item, weightKg: 70, reps: 3, type: .failure)
        XCTAssertEqual(item.sortedSets.count, 4)
        XCTAssertEqual(added.order, 3)
        XCTAssertTrue(added.isCompleted)
        XCTAssertEqual(session.incompleteSetCount, 0)

        try service.updateSet(added, weightKg: 72.5, reps: 4, type: .warmup)
        XCTAssertEqual([added.weightKg, Double(added.reps)], [72.5, 4])
        XCTAssertEqual(added.type, .warmup)

        try service.removeSetFromHistory(item.sortedSets[0])
        XCTAssertEqual(item.sortedSets.map(\.order), [0, 1, 2])
    }

    func testRemovingLastSetOfAnExerciseRemovesTheExercise() throws {
        let session = try closedSession()
        let squatItem = session.sortedExercises[1]
        try service.removeSetFromHistory(squatItem.sortedSets[0])
        XCTAssertEqual(squatItem.sortedSets.count, 1)
        try service.removeSetFromHistory(squatItem.sortedSets[0])
        XCTAssertEqual(session.sortedExercises.map { $0.exercise?.name }, ["Panca"])
        XCTAssertEqual(session.sortedExercises.map(\.order), [0])
    }

    func testClosedSessionMustKeepOneCompletedSet() throws {
        let template = try service.createTemplate(name: "Mini", exercises: [(panca, 1, 8, 60)])
        let session = try service.startSession(from: template, at: t0)
        try service.completeSet(session.sortedExercises[0].sortedSets[0], weightKg: 40, reps: 10)
        try service.finish(session, at: t0.addingTimeInterval(60))

        XCTAssertThrowsError(try service.removeSetFromHistory(session.sortedExercises[0].sortedSets[0])) {
            XCTAssertEqual($0 as? WorkoutServiceError, .sessionWouldBeEmpty)
        }
        XCTAssertThrowsError(try service.removeExerciseFromHistory(session.sortedExercises[0])) {
            XCTAssertEqual($0 as? WorkoutServiceError, .sessionWouldBeEmpty)
        }
        XCTAssertEqual(session.completedSetCount, 1, "non è cambiato nulla")
        // L'unica via d'uscita è eliminare l'intera sessione.
        try service.deleteSession(session)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testAddAndRemoveExerciseInHistory() throws {
        let session = try closedSession()
        let curl = try service.createExercise(name: "Curl")
        let item = try service.addExerciseToHistory(curl, to: session, weightKg: 20, reps: 12)
        XCTAssertEqual(item.order, 2)
        XCTAssertEqual(item.sortedSets.count, 1)
        XCTAssertTrue(item.sortedSets[0].isCompleted)
        XCTAssertEqual(session.incompleteSetCount, 0)

        try service.removeExerciseFromHistory(session.sortedExercises[0])
        XCTAssertEqual(session.sortedExercises.map { $0.exercise?.name }, ["Squat", "Curl"])
        XCTAssertEqual(session.sortedExercises.map(\.order), [0, 1])

        try service.archiveExercise(squat)
        XCTAssertThrowsError(try service.addExerciseToHistory(squat, to: session)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .exerciseArchived("Squat"))
        }
    }

    func testCreatePastSession() throws {
        let start = t0, end = t0.addingTimeInterval(3_000)
        let session = try service.createPastSession(name: " ", startedAt: start, endedAt: end, exercise: panca, weightKg: 60, reps: 5)
        XCTAssertEqual(session.name, "Allenamento")
        XCTAssertFalse(session.isOpen)
        XCTAssertEqual(session.completedSetCount, 1)
        XCTAssertEqual(session.sortedExercises[0].sortedSets[0].weightKg, 60)
        XCTAssertNil(try service.openSession())

        XCTAssertThrowsError(try service.createPastSession(name: "x", startedAt: end, endedAt: start, exercise: panca, weightKg: 1, reps: 1)) {
            XCTAssertEqual($0 as? WorkoutServiceError, .endBeforeStart)
        }
        // Una sessione registrata a posteriori conta come storico per le serie precompilate.
        XCTAssertEqual(try service.lastPerformance(of: panca)?.first?.weightKg, 60)
    }
}

private extension ModelContext {
    func fetchSafely<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? fetch(FetchDescriptor<T>())) ?? []
    }
}
