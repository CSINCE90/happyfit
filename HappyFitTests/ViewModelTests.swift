import XCTest
import SwiftData
@testable import HappyFit

/// Test dei ViewModel principali (SwiftData in memoria, UserDefaults isolato).
@MainActor
final class ViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: WorkoutService!
    private var defaults: UserDefaults!
    private var panca: Exercise!
    private var squat: Exercise!
    private var template: WorkoutTemplate!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = ModelContext(container)
        service = WorkoutService(context: context)
        let suite = "HappyFitTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        panca = try service.createExercise(name: "Panca piana", muscleGroup: .petto)
        squat = try service.createExercise(name: "Squat", muscleGroup: .gambe)
        template = try service.createTemplate(name: "Push", exercises: [(panca, 3, 8, 120), (squat, 2, 5, 60)])
    }

    private func makeActive(at date: Date? = nil) throws -> ActiveWorkoutViewModel {
        let session = try service.startSession(from: template, at: date ?? t0)
        return ActiveWorkoutViewModel(session: session, context: context, defaults: defaults)
    }

    // MARK: - ActiveWorkoutViewModel

    func testCompletingSetStartsRestFromExercise() throws {
        let vm = try makeActive()
        let entry = vm.session.sortedExercises[0].sortedSets[0]
        vm.toggleComplete(entry, now: t0)

        XCTAssertTrue(entry.isCompleted)
        XCTAssertEqual(vm.restRemainingSeconds, 120)
        XCTAssertNotNil(vm.restTimer)
        XCTAssertEqual(vm.completedSetCount, 1)

        // Togliere la spunta non avvia il timer.
        vm.skipRest()
        vm.toggleComplete(entry, now: t0)
        XCTAssertFalse(entry.isCompleted)
        XCTAssertNil(vm.restTimer)
    }

    func testRestTimerTickSkipAddAndFinish() throws {
        let vm = try makeActive()
        var finished = 0
        vm.onRestFinished = { finished += 1 }

        vm.startRest(seconds: 30, now: t0)
        vm.tick(now: t0.addingTimeInterval(10))
        XCTAssertEqual(vm.restRemainingSeconds, 20)

        vm.addRest(seconds: 15, now: t0.addingTimeInterval(10))
        XCTAssertEqual(vm.restRemainingSeconds, 35)

        vm.tick(now: t0.addingTimeInterval(44.5))
        XCTAssertEqual(vm.restRemainingSeconds, 1)
        XCTAssertEqual(finished, 0)

        vm.tick(now: t0.addingTimeInterval(46))
        XCTAssertNil(vm.restTimer)
        XCTAssertEqual(finished, 1)

        // Salta non fa vibrare.
        vm.startRest(seconds: 30, now: t0)
        vm.skipRest()
        XCTAssertNil(vm.restTimer)
        XCTAssertEqual(finished, 1)

        // Recupero a zero: nessun timer.
        vm.startRest(seconds: 0, now: t0)
        XCTAssertNil(vm.restTimer)
    }

    func testWeightStepComesFromSettings() throws {
        let vm = try makeActive()
        let entry = vm.session.sortedExercises[0].sortedSets[0]

        vm.adjustWeight(entry, direction: 1)
        XCTAssertEqual(entry.weightKg, 2.5) // predefinito

        defaults.set(5.0, forKey: AppSettings.weightStepKey)
        vm.adjustWeight(entry, direction: 1)
        XCTAssertEqual(entry.weightKg, 7.5)

        vm.adjustWeight(entry, direction: -1)
        vm.adjustWeight(entry, direction: -1)
        vm.adjustWeight(entry, direction: -1)
        XCTAssertEqual(entry.weightKg, 0, "il peso non scende sotto zero")

        vm.adjustReps(entry, delta: 2)
        XCTAssertEqual(entry.reps, 10)
        vm.setType(entry, .warmup)
        XCTAssertEqual(entry.type, .warmup)
    }

    func testPreviousSummaryAndAddExerciseUseSettings() throws {
        // Storico: panca 50×8, 60×6.
        let first = try service.startSession(from: template, at: t0.addingTimeInterval(-86_400))
        let sets = first.sortedExercises[0].sortedSets
        try service.completeSet(sets[0], weightKg: 50, reps: 8)
        try service.completeSet(sets[1], weightKg: 60, reps: 6)
        try service.finish(first, at: t0.addingTimeInterval(-80_000))

        let vm = try makeActive()
        XCTAssertEqual(vm.previousSummary(for: vm.session.sortedExercises[0]), "50 × 8 · 60 × 6")
        XCTAssertNil(vm.previousSummary(for: vm.session.sortedExercises[1]))

        defaults.set(75, forKey: AppSettings.defaultRestKey)
        vm.addExercise(try service.createExercise(name: "Curl"))
        vm.addExercise(try service.createExercise(name: "Dip", defaultRestSeconds: 45))
        XCTAssertEqual(vm.session.sortedExercises[2].restSeconds, 75)
        XCTAssertEqual(vm.session.sortedExercises[3].restSeconds, 45)
    }

    func testFinishDeletesIncompleteAfterwards() throws {
        let vm = try makeActive()
        let panca = vm.session.sortedExercises[0]
        vm.toggleComplete(panca.sortedSets[0], now: t0)
        XCTAssertEqual(vm.incompleteSetCount, 4)
        XCTAssertFalse(vm.canDiscard)

        XCTAssertTrue(vm.finish(at: t0.addingTimeInterval(100)))
        XCTAssertTrue(vm.didEnd)
        XCTAssertNil(vm.restTimer)
        XCTAssertEqual(vm.incompleteSetCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 1)
    }

    func testFinishWithoutCompletedSetsFailsAndDiscardWorks() throws {
        let vm = try makeActive()
        XCTAssertTrue(vm.canDiscard)
        XCTAssertFalse(vm.finish())
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.didEnd)

        XCTAssertTrue(vm.discard())
        XCTAssertTrue(vm.didEnd)
        XCTAssertNil(try service.openSession())
    }

    func testAddAndRemoveSetsAndExercises() throws {
        let vm = try makeActive()
        let item = vm.session.sortedExercises[0]
        vm.addSet(to: item)
        XCTAssertEqual(item.sortedSets.count, 4)
        vm.removeSet(item.sortedSets[0])
        XCTAssertEqual(item.sortedSets.count, 3)
        vm.setRest(item, seconds: 200)
        XCTAssertEqual(item.restSeconds, 200)
        vm.removeExercise(item)
        XCTAssertEqual(vm.session.sortedExercises.count, 1)
    }

    // MARK: - ExerciseCatalogViewModel

    func testCatalogSearchAndGroupFilter() throws {
        let vm = ExerciseCatalogViewModel(context: context)
        let all = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(vm.visible(from: all).map(\.name), ["Panca piana", "Squat"])

        vm.searchText = "pan"
        XCTAssertEqual(vm.visible(from: all).map(\.name), ["Panca piana"])
        vm.searchText = ""
        vm.selectedGroup = .gambe
        XCTAssertEqual(vm.visible(from: all).map(\.name), ["Squat"])

        vm.archive(squat)
        XCTAssertTrue(vm.visible(from: all).isEmpty)
        XCTAssertEqual(vm.archived(from: all).map(\.name), ["Squat"])
        vm.unarchive(squat)
        XCTAssertEqual(vm.visible(from: all).count, 1)
    }

    func testCatalogDuplicateNameShowsClearError() throws {
        let vm = ExerciseCatalogViewModel(context: context)
        XCTAssertFalse(vm.create(name: "SQUAT", group: nil, defaultRestSeconds: nil))
        XCTAssertEqual(vm.errorMessage, "Esiste già un esercizio chiamato \"SQUAT\".")

        XCTAssertTrue(vm.create(name: "Stacco", group: .schiena, defaultRestSeconds: 150))
        XCTAssertNil(vm.errorMessage)

        // Rinomina in un nome già usato: non cambia nulla.
        XCTAssertFalse(vm.update(panca, name: "squat", group: .core, defaultRestSeconds: nil))
        XCTAssertEqual(panca.name, "Panca piana")
        XCTAssertEqual(panca.muscleGroup, .petto)
        XCTAssertTrue(vm.update(panca, name: "Panca", group: .spalle, defaultRestSeconds: 100))
        XCTAssertEqual(panca.muscleGroup, .spalle)
        XCTAssertEqual(panca.defaultRestSeconds, 100)
    }

    // MARK: - TemplatesViewModel

    func testTemplatesListOperations() throws {
        let vm = TemplatesViewModel(context: context, defaults: defaults)
        XCTAssertNil(vm.create(name: " "))
        XCTAssertEqual(vm.errorMessage, "Il nome della scheda non può essere vuoto.")

        let legs = try XCTUnwrap(vm.create(name: "Gambe"))
        let copy = try XCTUnwrap(vm.duplicate(template))
        XCTAssertEqual(try service.templates().map(\.name), ["Push", "Gambe", "Push (copia)"])

        // Sposta l'ultima in cima.
        vm.move(try service.templates(), from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(try service.templates().map(\.name), ["Push (copia)", "Push", "Gambe"])

        XCTAssertTrue(vm.rename(legs, to: "Leg day"))
        vm.delete(copy)
        XCTAssertEqual(try service.templates().map(\.name), ["Push", "Leg day"])
        XCTAssertEqual(try service.templates().map(\.order), [0, 1])
    }

    func testTemplateEditorOperations() throws {
        let vm = TemplatesViewModel(context: context, defaults: defaults)
        defaults.set(100, forKey: AppSettings.defaultRestKey)
        let curl = try service.createExercise(name: "Curl")

        vm.addExercise(curl, to: template)
        XCTAssertEqual(template.sortedExercises.last?.restSeconds, 100)

        let row = template.sortedExercises[0]
        vm.update(row, sets: 5, reps: 3, restSeconds: 30)
        XCTAssertEqual([row.targetSets, row.targetReps, row.restSeconds], [5, 3, 30])

        vm.moveExercises(of: template, from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(template.sortedExercises.first?.exercise?.name, "Curl")

        vm.removeExercises(of: template, at: IndexSet(integer: 0))
        XCTAssertEqual(template.sortedExercises.map { $0.exercise?.name }, ["Panca piana", "Squat"])
        XCTAssertEqual(template.sortedExercises.map(\.order), [0, 1])
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.clock(90), "1:30")
        XCTAssertEqual(Formatting.rest(90), "1 min 30 s")
        XCTAssertEqual(Formatting.rest(45), "45 s")
        XCTAssertEqual(Formatting.parseNumber("52,5"), 52.5)
        XCTAssertNil(Formatting.parseNumber("abc"))
    }
}
