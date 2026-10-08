import XCTest
@testable import HappyFitWatch

/// Avvisi registrati invece che programmati davvero.
@MainActor
final class FakeRestNotifications: RestNotificationScheduling {
    var notDetermined = true
    var grant = true
    private(set) var requested = 0
    private(set) var scheduled: [(Date, String?)] = []
    private(set) var cancelled = 0

    func needsAuthorization() async -> Bool { notDetermined }
    func requestAuthorization() async -> Bool { requested += 1; notDetermined = false; return grant }
    func schedule(at date: Date, exerciseName: String?) { scheduled.append((date, exerciseName)) }
    func cancel() { cancelled += 1 }
}

@MainActor
final class WatchSessionViewModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var defaults: UserDefaults!
    private var fake: FakeRestNotifications!
    private var pancaID = UUID()

    override func setUp() async throws {
        let suite = "watch-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        fake = FakeRestNotifications()
    }

    private func set(_ order: Int, _ weight: Double, _ reps: Int, done: Bool = false) -> SetEntryDTO {
        SetEntryDTO(id: UUID(), order: order, weightKg: weight, reps: reps, type: .normal, completedAt: done ? t0 : nil)
    }

    /// Panca (2 serie, recupero 90 s, con storico) e Curl (1 serie, recupero 60 s).
    private func makeViewModel(session: WorkoutSessionDTO? = nil) -> WatchSessionViewModel {
        let s = session ?? WorkoutSessionDTO(
            id: UUID(), name: "Push", startedAt: t0, endedAt: nil,
            exercises: [
                SessionExerciseDTO(id: UUID(), exercise: ExerciseDTO(id: pancaID, name: "Panca"), order: 0, restSeconds: 90, sets: [set(0, 50, 8), set(1, 50, 8)]),
                SessionExerciseDTO(id: UUID(), exercise: ExerciseDTO(id: UUID(), name: "Curl"), order: 1, restSeconds: 60, sets: [set(0, 10, 12)])
            ],
            previousSets: [pancaID: [set(0, 47.5, 8, done: true)]]
        )
        let vm = WatchSessionViewModel(remote: InMemoryWorkoutRemote(session: s), notifications: fake, defaults: defaults)
        vm.onRestFinished = {}
        return vm
    }

    func testScreens() {
        let none = WatchSessionViewModel(remote: InMemoryWorkoutRemote(session: nil), notifications: fake, defaults: defaults)
        XCTAssertEqual(none.screen, .noSession)
        let vm = makeViewModel()
        XCTAssertEqual(vm.screen, .set(SetPosition(exerciseIndex: 0, setIndex: 0)))
        XCTAssertEqual(vm.shownExercise?.exercise.name, "Panca")
        XCTAssertEqual(vm.setLabel, "Serie 1 di 2")
        XCTAssertEqual(vm.previousSummary, "Ultima volta: 47,5 × 8")
    }

    func testCompleteActsOnShownExerciseAndAdvances() async {
        let vm = makeViewModel()
        // Scelgo Curl dall'elenco: "Completa serie" agisce su Curl, non sulla Panca corrente.
        vm.show(exerciseID: vm.exercises[1].id)
        XCTAssertEqual(vm.shownExercise?.exercise.name, "Curl")
        XCTAssertNil(vm.previousSummary, "senza storico la riga si nasconde")
        vm.completeShownSet(now: t0)
        XCTAssertEqual(vm.exercises[1].sets[0].completedAt, t0)
        XCTAssertNil(vm.exercises[0].sets[0].completedAt)
        // Curl finito → torna al primo esercizio con serie incomplete; recupero di Curl (60 s).
        XCTAssertEqual(vm.shownExercise?.exercise.name, "Panca")
        XCTAssertEqual(vm.restTimer?.totalSeconds, 60)
        await vm.notificationTask?.value
    }

    func testAllDoneStopsWithoutRest() {
        let vm = makeViewModel()
        vm.completeShownSet(now: t0)
        vm.skipRest()
        vm.completeShownSet(now: t0)
        vm.skipRest()
        XCTAssertEqual(vm.shownExercise?.exercise.name, "Curl")
        vm.completeShownSet(now: t0)
        XCTAssertEqual(vm.screen, .allDone)
        XCTAssertNil(vm.restTimer, "dopo l'ultima serie non parte il recupero")
    }

    func testCrownChangesSelectedValueWithStepAndLimits() {
        let vm = makeViewModel()
        vm.crownValue = 80
        XCTAssertEqual(vm.shownSet?.weightKg, 50, "senza selezione la Crown non cambia nulla")

        vm.select(.weight)
        XCTAssertEqual(vm.crownStep, 2.5)
        vm.crownValue = 51.1
        XCTAssertEqual(vm.shownSet?.weightKg, 50, "arrotondato al passo da 2,5")
        vm.crownValue = 52.4
        XCTAssertEqual(vm.shownSet?.weightKg, 52.5)
        vm.crownValue = 9999
        XCTAssertEqual(vm.shownSet?.weightKg, SessionLogic.maxWeightKg)

        vm.select(.reps)
        XCTAssertEqual(vm.crownRange, 0...100)
        vm.crownValue = 10
        XCTAssertEqual(vm.shownSet?.reps, 10)
        vm.crownValue = -4
        XCTAssertEqual(vm.shownSet?.reps, 0)

        vm.select(.reps)
        XCTAssertNil(vm.selectedField, "secondo tocco: deseleziona")
    }

    func testRestTimerTickAddSkipAndForegroundHaptic() {
        let vm = makeViewModel()
        var buzz = 0
        vm.onRestFinished = { buzz += 1 }
        vm.startRest(seconds: 30, now: t0)
        vm.tick(now: t0.addingTimeInterval(10))
        XCTAssertEqual(vm.restRemainingSeconds, 20)
        vm.addRest(seconds: 15, now: t0.addingTimeInterval(10))
        XCTAssertEqual(vm.restRemainingSeconds, 35)
        vm.addRest(seconds: -15, now: t0.addingTimeInterval(10))
        XCTAssertEqual(vm.restRemainingSeconds, 20)
        vm.tick(now: t0.addingTimeInterval(31))
        XCTAssertNil(vm.restTimer)
        XCTAssertEqual(buzz, 1)
    }

    func testFirstRestExplainsThenAsksAndSchedules() async {
        let vm = makeViewModel()
        vm.startRest(seconds: 90, now: Date())
        await vm.notificationTask?.value
        XCTAssertTrue(vm.showPermissionExplanation, "prima volta: spiegazione prima della richiesta")
        XCTAssertTrue(fake.scheduled.isEmpty)

        await vm.answerPermission(allow: true)
        XCTAssertFalse(vm.showPermissionExplanation)
        XCTAssertEqual(fake.requested, 1)
        XCTAssertEqual(fake.scheduled.count, 1)
        XCTAssertEqual(fake.scheduled.first?.1, "Panca")
        XCTAssertEqual(fake.scheduled.first?.0, vm.restTimer?.endDate)
    }

    func testDeclinedPermissionIsNotAskedAgain() async {
        let vm = makeViewModel()
        vm.startRest(seconds: 90)
        await vm.notificationTask?.value
        await vm.answerPermission(allow: false)
        XCTAssertEqual(fake.requested, 0)
        vm.skipRest()
        vm.startRest(seconds: 90)
        await vm.notificationTask?.value
        XCTAssertFalse(vm.showPermissionExplanation, "già spiegato: non si chiede di nuovo")
    }

    func testNotificationRescheduledOnPlusMinusAndCancelledOnSkip() async {
        fake.notDetermined = false
        let vm = makeViewModel()
        vm.startRest(seconds: 90, now: t0)
        await vm.notificationTask?.value
        XCTAssertEqual(fake.scheduled.count, 1)
        let first = fake.scheduled[0].0
        vm.addRest(seconds: 15, now: t0)
        XCTAssertEqual(fake.scheduled.count, 2)
        XCTAssertEqual(fake.scheduled[1].0, first.addingTimeInterval(15), "riprogrammata con il nuovo orario")
        let cancelledBefore = fake.cancelled
        vm.skipRest()
        XCTAssertEqual(fake.cancelled, cancelledBefore + 1, "saltando il recupero l'avviso si annulla")
    }
}
