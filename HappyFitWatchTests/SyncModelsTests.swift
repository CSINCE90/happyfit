import XCTest
@testable import HappyFitWatch

/// Test del protocollo dei messaggi in Shared (valgono per iPhone e Watch).
final class SyncModelsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSession(exercises: Int, sets: Int, previous: Bool) -> WorkoutSessionDTO {
        var previousSets: [UUID: [SetEntryDTO]] = [:]
        let exerciseDTOs = (0..<exercises).map { e -> SessionExerciseDTO in
            let catalogID = UUID()
            let dtos = (0..<sets).map { s in
                SetEntryDTO(id: UUID(), order: s, weightKg: 52.5, reps: 8, type: .normal, completedAt: s % 2 == 0 ? t0 : nil)
            }
            if previous { previousSets[catalogID] = dtos }
            return SessionExerciseDTO(id: UUID(), exercise: ExerciseDTO(id: catalogID, name: "Esercizio numero \(e) con un nome piuttosto lungo"), order: e, restSeconds: 90, sets: dtos)
        }
        return WorkoutSessionDTO(id: UUID(), name: "Allenamento molto lungo", startedAt: t0, endedAt: nil, exercises: exerciseDTOs, previousSets: previousSets)
    }

    private func makeState(_ session: WorkoutSessionDTO?, revision: Int64 = 1) -> SyncState {
        SyncState(revision: revision, sentAt: t0, session: session, restEnd: t0.addingTimeInterval(90), restTotalSeconds: 90,
                  settings: SyncSettings(weightStep: 2.5, accentRaw: "volt"))
    }

    // MARK: - Codifica

    func testStateRoundTripThroughEnvelope() throws {
        let state = makeState(makeSession(exercises: 3, sets: 4, previous: true), revision: 1_700_000_000_123)
        let envelope = try XCTUnwrap(SyncCodec.stateEnvelope(state))
        XCTAssertEqual(SyncCodec.kind(of: envelope), .state)
        XCTAssertEqual(SyncCodec.decodeState(envelope), state)
        // Il dizionario contiene solo tipi property list.
        XCTAssertTrue(envelope.value.values.allSatisfy { $0 is String || $0 is Data })
        XCTAssertNil(SyncCodec.decodeCommand(envelope), "un messaggio di stato non è un comando")
    }

    func testCommandsRoundTripAndAck() throws {
        let sessionID = UUID(), setID = UUID(), exerciseID = UUID()
        let commands: [WatchCommand] = [
            WatchCommand(sessionID: sessionID, sentAt: t0, action: .completeSet(setID: setID, exerciseID: exerciseID)),
            WatchCommand(sessionID: sessionID, sentAt: t0, action: .setValues(setID: setID, exerciseID: exerciseID, weightKg: 55, reps: nil)),
            WatchCommand(sessionID: sessionID, sentAt: t0, action: .setRestEnd(endDate: t0.addingTimeInterval(60), totalSeconds: 60)),
            WatchCommand(sessionID: sessionID, sentAt: t0, action: .skipRest)
        ]
        for command in commands {
            let envelope = try XCTUnwrap(SyncCodec.envelope(.command, command))
            XCTAssertEqual(SyncCodec.decodeCommand(envelope), command)
            XCTAssertEqual(SyncCodec.ackID(SyncCodec.ackEnvelope(for: command.id)), command.id)
        }
        XCTAssertEqual(commands.map(\.isTimeSensitive), [false, false, true, true], "solo i comandi sul recupero sono sensibili al tempo")
        XCTAssertEqual(SyncCodec.kind(of: SyncCodec.requestStateEnvelope()), .requestState)
        XCTAssertNil(SyncCodec.decodeState(Envelope(value: ["kind": "state", "payload": Data([1, 2, 3])])), "payload illeggibile: ignorato")
    }

    func testCommandAlwaysNamesTheSetAndSession() {
        // Il comando contiene gli id di serie e sessione: non esiste una forma "prossima serie incompleta".
        let command = WatchCommand(sessionID: UUID(), action: .completeSet(setID: UUID(), exerciseID: UUID()))
        if case .completeSet(let setID, let exerciseID) = command.action {
            XCTAssertNotEqual(setID, exerciseID)
        } else {
            XCTFail()
        }
    }

    // MARK: - Revisione (punto 3)

    func testRevisionIsIncreasingAndSurvivesRestartAndClockRollback() {
        let suite = UserDefaults(suiteName: "rev-\(UUID().uuidString)")!
        var now = t0
        let first = RevisionClock(defaults: suite, now: { now })
        let a = first.next()
        let b = first.next()
        XCTAssertGreaterThan(b, a, "più invii nello stesso millisecondo: comunque crescenti")

        // Riavvio dell'app (nuova istanza, stessi defaults) con l'orologio tornato indietro di un'ora.
        now = t0.addingTimeInterval(-3600)
        let restarted = RevisionClock(defaults: suite, now: { now })
        XCTAssertGreaterThan(restarted.next(), b, "dopo il riavvio non riparte da zero né torna indietro")
    }

    func testRevisionNeverRestartsBelowAnEarlierOneEvenWithEmptyDefaults() {
        // Defaults vuoti (per esempio app reinstallata): si parte dai millisecondi dell'epoca, non da 0.
        let clock = RevisionClock(defaults: UserDefaults(suiteName: "rev-\(UUID().uuidString)")!, now: { self.t0 })
        XCTAssertEqual(clock.next(), Int64(t0.timeIntervalSince1970 * 1000))
        let earlier = RevisionClock(defaults: UserDefaults(suiteName: "rev-\(UUID().uuidString)")!, now: { self.t0.addingTimeInterval(-10) })
        XCTAssertLessThan(earlier.next(), Int64(t0.timeIntervalSince1970 * 1000), "il tempo reale fa da riferimento comune")
    }

    // MARK: - Dimensione (punto 8)

    func testTypicalAndLargeSessionsStayUnderTheLimit() throws {
        let typical = makeState(makeSession(exercises: 6, sets: 4, previous: true))
        let typicalSize = SyncCodec.encodedSize(typical)
        XCTAssertLessThan(typicalSize, SyncLimits.softPayloadBytes, "sessione tipica (\(typicalSize) byte)")

        // Sessione molto grande, con "ultima volta" per ogni esercizio.
        let large = makeState(makeSession(exercises: 20, sets: 10, previous: true))
        let largeSize = SyncCodec.encodedSize(large)
        let trimmedSize = SyncCodec.encodedSize(large.trimmed())
        print("DIMENSIONI stato: tipico \(typicalSize) B, grande completo \(largeSize) B, grande senza storico \(trimmedSize) B, tetto prudente \(SyncLimits.softPayloadBytes) B")
        XCTAssertGreaterThan(largeSize, SyncLimits.softPayloadBytes, "il caso grande supera il tetto: serve il ripiego")
        XCTAssertLessThan(trimmedSize, SyncLimits.softPayloadBytes, "senza storico ci sta")

        // L'invio ripiega da solo sullo stato senza storico e resta decodificabile.
        let envelope = try XCTUnwrap(SyncCodec.stateEnvelope(large))
        let decoded = try XCTUnwrap(SyncCodec.decodeState(envelope))
        XCTAssertTrue(decoded.session?.previousSets.isEmpty == true)
        XCTAssertEqual(decoded.session?.exercises, large.session?.exercises, "serie ed esercizi restano interi")
        let payload = try XCTUnwrap(envelope.value["payload"] as? Data)
        XCTAssertLessThan(payload.count, SyncLimits.softPayloadBytes)
    }
}
