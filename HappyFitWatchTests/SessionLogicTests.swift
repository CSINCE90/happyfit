import XCTest
@testable import HappyFitWatch

/// Test della logica pura di Shared (esercizio e serie correnti, ultima volta, modifiche ai DTO).
final class SessionLogicTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func set(_ order: Int, _ weight: Double, _ reps: Int, done: Bool = false) -> SetEntryDTO {
        SetEntryDTO(id: UUID(), order: order, weightKg: weight, reps: reps, type: .normal, completedAt: done ? t0 : nil)
    }

    private func exercise(_ name: String, order: Int, sets: [SetEntryDTO], id: UUID = UUID()) -> SessionExerciseDTO {
        SessionExerciseDTO(id: UUID(), exercise: ExerciseDTO(id: id, name: name), order: order, restSeconds: 90, sets: sets)
    }

    private func session(_ exercises: [SessionExerciseDTO], previous: [UUID: [SetEntryDTO]] = [:]) -> WorkoutSessionDTO {
        WorkoutSessionDTO(id: UUID(), name: "Push", startedAt: t0, endedAt: nil, exercises: exercises, previousSets: previous)
    }

    func testCurrentIsFirstExerciseWithIncompleteSetAndItsFirstIncompleteSet() {
        // Ordini volutamente non in sequenza nell'array: conta `order`.
        let s = session([
            exercise("Squat", order: 1, sets: [set(1, 60, 5), set(0, 60, 5, done: true)]),
            exercise("Panca", order: 0, sets: [set(0, 50, 8, done: true), set(1, 50, 8, done: true)])
        ])
        XCTAssertEqual(SessionLogic.current(in: s), SetPosition(exerciseIndex: 1, setIndex: 1))
        XCTAssertEqual(SessionLogic.orderedExercises(s).map(\.exercise.name), ["Panca", "Squat"])
    }

    func testCurrentIsNilWhenEverythingIsDoneOrEmpty() {
        XCTAssertNil(SessionLogic.current(in: session([exercise("Panca", order: 0, sets: [set(0, 50, 8, done: true)])])))
        XCTAssertNil(SessionLogic.current(in: session([])))
        XCTAssertNil(SessionLogic.current(in: session([exercise("Vuoto", order: 0, sets: [])])))
    }

    func testDisplayedUsesPreferredExerciseUntilItIsFinished() {
        let panca = exercise("Panca", order: 0, sets: [set(0, 50, 8), set(1, 50, 8)])
        let curl = exercise("Curl", order: 1, sets: [set(0, 10, 12, done: true), set(1, 10, 12)])
        let s = session([panca, curl])
        XCTAssertEqual(SessionLogic.displayed(in: s, preferredExerciseID: curl.id), SetPosition(exerciseIndex: 1, setIndex: 1))
        XCTAssertEqual(SessionLogic.displayed(in: s, preferredExerciseID: nil), SetPosition(exerciseIndex: 0, setIndex: 0))
        // Esercizio scelto finito → torna alla serie corrente.
        let done = SessionLogic.completingSet(curl.sets[1].id, of: curl.id, in: s, at: t0)
        XCTAssertEqual(SessionLogic.displayed(in: done, preferredExerciseID: curl.id), SetPosition(exerciseIndex: 0, setIndex: 0))
        // Id sconosciuto → serie corrente.
        XCTAssertEqual(SessionLogic.displayed(in: s, preferredExerciseID: UUID()), SetPosition(exerciseIndex: 0, setIndex: 0))
    }

    func testPreviousSetSameNumberOtherwiseLastCompleted() {
        let catalogID = UUID()
        let previous = [set(0, 50, 8, done: true), set(1, 55, 6, done: true)]
        let panca = exercise("Panca", order: 0, sets: [set(0, 0, 0), set(1, 0, 0), set(2, 0, 0)], id: catalogID)
        let s = session([panca], previous: [catalogID: previous])
        XCTAssertEqual(SessionLogic.previousSet(in: s, exercise: panca, setIndex: 0)?.weightKg, 50)
        XCTAssertEqual(SessionLogic.previousSet(in: s, exercise: panca, setIndex: 1)?.weightKg, 55)
        XCTAssertEqual(SessionLogic.previousSet(in: s, exercise: panca, setIndex: 2)?.weightKg, 55, "oltre: l'ultima completata")
        let nuovo = exercise("Nuovo", order: 1, sets: [set(0, 0, 0)])
        XCTAssertNil(SessionLogic.previousSet(in: s, exercise: nuovo, setIndex: 0), "senza storico: niente riga")
    }

    func testCompletingAndSettingValuesWithLimits() {
        let panca = exercise("Panca", order: 0, sets: [set(0, 50, 8)])
        let s = session([panca])
        let setID = panca.sets[0].id
        let done = SessionLogic.completingSet(setID, of: panca.id, in: s, at: t0)
        XCTAssertEqual(done.exercises[0].sets[0].completedAt, t0)
        XCTAssertNil(s.exercises[0].sets[0].completedAt, "l'originale non cambia")

        let heavy = SessionLogic.settingValues(of: setID, of: panca.id, in: s, weightKg: 9999, reps: -3)
        XCTAssertEqual(heavy.exercises[0].sets[0].weightKg, SessionLogic.maxWeightKg)
        XCTAssertEqual(heavy.exercises[0].sets[0].reps, 0)
        let light = SessionLogic.settingValues(of: setID, of: panca.id, in: s, weightKg: -1, reps: 500)
        XCTAssertEqual(light.exercises[0].sets[0].weightKg, 0)
        XCTAssertEqual(light.exercises[0].sets[0].reps, SessionLogic.maxReps)
        // Id sconosciuti: nessuna modifica.
        XCTAssertEqual(SessionLogic.completingSet(UUID(), of: panca.id, in: s, at: t0), s)
    }

    func testProgress() {
        let e = exercise("Panca", order: 0, sets: [set(0, 50, 8, done: true), set(1, 50, 8), set(2, 50, 8)])
        XCTAssertEqual(SessionLogic.progress(e).completed, 1)
        XCTAssertEqual(SessionLogic.progress(e).total, 3)
    }

    func testRestTimerStillWorksFromShared() {
        var timer = RestTimer(seconds: 90, now: t0)
        XCTAssertEqual(timer.remainingSeconds(at: t0.addingTimeInterval(30)), 60)
        timer.add(seconds: 15)
        XCTAssertEqual(timer.totalSeconds, 105)
        XCTAssertTrue(timer.isFinished(at: t0.addingTimeInterval(105)))
    }
}
