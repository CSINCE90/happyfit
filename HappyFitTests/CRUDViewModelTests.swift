import XCTest
import SwiftData
@testable import HappyFit

/// Test dei ViewModel del CRUD completo: eliminazione esercizi, storico modificabile, schede.
@MainActor
final class CRUDViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: WorkoutService!
    private var panca: Exercise!
    private var squat: Exercise!
    private var curl: Exercise!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = ModelContext(container)
        service = WorkoutService(context: context)
        panca = try service.createExercise(name: "Panca")
        squat = try service.createExercise(name: "Squat")
        curl = try service.createExercise(name: "Curl")
    }

    private func closedSession() throws -> WorkoutSession {
        let template = try service.createTemplate(name: "Push", exercises: [(panca, 2, 8, 60)])
        let session = try service.startSession(from: template, at: t0)
        for entry in session.sortedExercises[0].sortedSets { try service.completeSet(entry, weightKg: 50, reps: 8, at: t0) }
        try service.finish(session, at: t0.addingTimeInterval(3_600))
        return session
    }

    // MARK: - Eliminazione esercizi

    func testUnusedExerciseIsDeletedAfterConfirmation() throws {
        let vm = ExerciseCatalogViewModel(context: context)
        vm.requestDelete(curl)
        XCTAssertEqual(vm.deletionPlan, .confirmDelete(curl))
        vm.cancelDeletion()
        XCTAssertNil(vm.deletionPlan)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 3, "annullare non elimina")

        vm.requestDelete(curl)
        XCTAssertTrue(vm.confirmDeletion())
        XCTAssertNil(vm.deletionPlan)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
    }

    func testExerciseInHistoryIsBlockedAndOffersArchive() throws {
        _ = try closedSession()
        let vm = ExerciseCatalogViewModel(context: context)
        vm.requestDelete(panca)
        XCTAssertEqual(vm.deletionPlan, .blocked(panca, sessionCount: 1))
        XCTAssertFalse(vm.confirmDeletion(), "un esercizio nello storico non si elimina")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 3)

        vm.requestDelete(panca)
        XCTAssertTrue(vm.archiveInsteadOfDeleting())
        XCTAssertTrue(panca.isArchived)
        XCTAssertNil(vm.deletionPlan)
    }

    func testExerciseOnlyInTemplatesListsThemAndRemovesAfterConfirmation() throws {
        let a = try service.createTemplate(name: "A", exercises: [(squat, 3, 5, 60), (curl, 3, 10, 60)])
        let b = try service.createTemplate(name: "B", exercises: [(squat, 3, 5, 60)])
        let vm = ExerciseCatalogViewModel(context: context)
        vm.requestDelete(squat)
        XCTAssertEqual(vm.deletionPlan, .confirmRemoveFromTemplates(squat, templates: ["A", "B"]))

        XCTAssertTrue(vm.confirmDeletion())
        XCTAssertEqual(a.sortedExercises.map { $0.exercise?.name }, ["Curl"])
        XCTAssertTrue(b.sortedExercises.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
    }

    // MARK: - Schede

    func testDeletingTemplateKeepsHistoryAndLeavesNoDanglingReference() throws {
        let session = try closedSession()
        let vm = TemplatesViewModel(context: context)
        vm.delete(try service.templates()[0])
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(try service.templates().isEmpty)
        XCTAssertEqual(session.completedSetCount, 2)
        XCTAssertNil(ModelContext(container).fetchAll(WorkoutSession.self).first?.template)
    }

    // MARK: - Storico modificabile

    func testSessionDetailEditing() throws {
        let session = try closedSession()
        let vm = SessionDetailViewModel(session: session, context: context)
        XCTAssertTrue(vm.rename(to: "Spinta"))
        XCTAssertEqual(session.name, "Spinta")
        XCTAssertFalse(vm.rename(to: " "))
        XCTAssertNotNil(vm.errorMessage)

        XCTAssertFalse(vm.updateTimes(start: t0, end: t0.addingTimeInterval(-60)))
        XCTAssertEqual(vm.errorMessage, "La fine dell'allenamento non può precedere l'inizio.")
        XCTAssertTrue(vm.updateTimes(start: t0, end: t0.addingTimeInterval(120)))
        XCTAssertNil(vm.errorMessage)

        let item = session.sortedExercises[0]
        vm.addSet(to: item)
        XCTAssertEqual(item.sortedSets.count, 3)
        XCTAssertEqual(item.sortedSets[2].weightKg, 50, "la nuova serie copia l'ultima")
        XCTAssertTrue(item.sortedSets[2].isCompleted)

        XCTAssertTrue(vm.updateSet(item.sortedSets[2], weightKg: 55, reps: 6, type: .failure))
        XCTAssertEqual(item.sortedSets[2].type, .failure)

        vm.addExercise(curl)
        XCTAssertEqual(session.sortedExercises.map { $0.exercise?.name }, ["Panca", "Curl"])
        vm.removeExercise(session.sortedExercises[1])
        XCTAssertEqual(session.sortedExercises.count, 1)
        XCTAssertFalse(vm.offerDeletingSession)
    }

    func testRemovingLastCompletedSetOffersDeletingTheSession() throws {
        let template = try service.createTemplate(name: "Mini", exercises: [(panca, 1, 8, 60)])
        let session = try service.startSession(from: template, at: t0)
        try service.completeSet(session.sortedExercises[0].sortedSets[0], weightKg: 40, reps: 10)
        try service.finish(session, at: t0.addingTimeInterval(60))

        let vm = SessionDetailViewModel(session: session, context: context)
        vm.removeSet(session.sortedExercises[0].sortedSets[0])
        XCTAssertTrue(vm.offerDeletingSession)
        XCTAssertNil(vm.errorMessage, "non è un errore: è una proposta")
        XCTAssertEqual(session.completedSetCount, 1)

        vm.removeExercise(session.sortedExercises[0])
        XCTAssertTrue(vm.offerDeletingSession)

        // La sessione si elimina solo quando la schermata è chiusa.
        vm.requestSessionDeletion()
        XCTAssertFalse(vm.offerDeletingSession)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertTrue(vm.performPendingDeletion())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertFalse(vm.performPendingDeletion())
    }

    func testHistoryViewModelCreatesAndDeletes() throws {
        let vm = HistoryViewModel(context: context)
        XCTAssertNil(vm.createPast(name: "x", startedAt: t0, endedAt: t0.addingTimeInterval(-1), exercise: panca, weightKg: 1, reps: 1))
        XCTAssertNotNil(vm.errorMessage)

        let session = try XCTUnwrap(vm.createPast(name: "Ieri", startedAt: t0, endedAt: t0.addingTimeInterval(1_800), exercise: panca, weightKg: 60, reps: 5))
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(session.name, "Ieri")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 1)

        XCTAssertTrue(vm.delete(session))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 3)
    }

    func testRenameOpenSession() throws {
        let template = try service.createTemplate(name: "Push", exercises: [(panca, 1, 8, 60)])
        let session = try service.startSession(from: template)
        let vm = ActiveWorkoutViewModel(session: session, context: context, defaults: UserDefaults(suiteName: "crud-\(UUID().uuidString)")!)
        vm.rename(to: "Spalle e petto")
        XCTAssertEqual(session.name, "Spalle e petto")
        // Scartare è possibile anche con serie completate.
        try service.completeSet(session.sortedExercises[0].sortedSets[0], weightKg: 10, reps: 10)
        XCTAssertTrue(vm.discard())
        XCTAssertNil(try service.openSession())
    }
}

private extension ModelContext {
    func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? fetch(FetchDescriptor<T>())) ?? []
    }
}
