import XCTest
@testable import HappyFitWatch

/// Trasporto finto per il Watch: registra gli invii e permette di simulare risposte e raggiungibilità.
@MainActor
final class FakeWatchTransport: ConnectivityTransport {
    weak var delegate: ConnectivityTransportDelegate?
    var isActivated = true
    var isReachable = true
    var canSendInBackground = true
    var receivedContext: Envelope?
    /// Risposta alla richiesta di stato (nil = l'iPhone non risponde).
    var stateReply: Envelope?
    var failSends = false
    private(set) var activateCount = 0
    private(set) var messages: [Envelope] = []
    private(set) var userInfos: [Envelope] = []

    func activate() { activateCount += 1 }
    func sendMessage(_ message: Envelope, reply: ((Envelope) -> Void)?, failure: ((Error) -> Void)?) {
        messages.append(message)
        if failSends { failure?(NSError(domain: "test", code: 1)); return }
        switch SyncCodec.kind(of: message) {
        case .requestState: if let stateReply { reply?(stateReply) }
        case .command:
            if let command = SyncCodec.decodeCommand(message) { reply?(SyncCodec.ackEnvelope(for: command.id)) }
        default: break
        }
    }
    func updateContext(_ context: Envelope) {}
    func transferUserInfo(_ userInfo: Envelope) { userInfos.append(userInfo) }

    var sentCommands: [WatchCommand] { messages.compactMap(SyncCodec.decodeCommand) }
    var queuedCommands: [WatchCommand] { userInfos.compactMap(SyncCodec.decodeCommand) }
}

@MainActor
final class RecordingNotifier: RestNotificationScheduling {
    private(set) var scheduled: [Date] = []
    private(set) var cancelled = 0
    func needsAuthorization() async -> Bool { false }
    func requestAuthorization() async -> Bool { true }
    func schedule(at date: Date, exerciseName: String?) { scheduled.append(date) }
    func cancel() { cancelled += 1 }
}

@MainActor
final class ConnectivityWorkoutRemoteTests: XCTestCase {
    private var transport: FakeWatchTransport!
    private var defaults: UserDefaults!
    private var notifier: RecordingNotifier!
    private var now = Date(timeIntervalSince1970: 1_700_000_000)
    private let sessionID = UUID()
    private let exerciseID = UUID()
    private let setA = UUID(), setB = UUID()

    override func setUp() async throws {
        transport = FakeWatchTransport()
        defaults = UserDefaults(suiteName: "remote-\(UUID().uuidString)")
        notifier = RecordingNotifier()
    }

    private func makeRemote() -> ConnectivityWorkoutRemote {
        ConnectivityWorkoutRemote(transport: transport, defaults: defaults, now: { [unowned self] in now }, restNotifier: notifier)
    }

    private func state(revision: Int64, session: Bool = true, completedA: Bool = false, weightA: Double = 50,
                       restEnd: Date? = nil, sentAt: Date? = nil, step: Double = 2.5, accent: String = "volt") -> SyncState {
        let dto = WorkoutSessionDTO(
            id: sessionID, name: "Push", startedAt: now.addingTimeInterval(-600), endedAt: nil,
            exercises: [SessionExerciseDTO(id: exerciseID, exercise: ExerciseDTO(id: UUID(), name: "Panca"), order: 0, restSeconds: 90, sets: [
                SetEntryDTO(id: setA, order: 0, weightKg: weightA, reps: 8, type: .normal, completedAt: completedA ? now : nil),
                SetEntryDTO(id: setB, order: 1, weightKg: 50, reps: 8, type: .normal, completedAt: nil)
            ])],
            previousSets: [:]
        )
        return SyncState(revision: revision, sentAt: sentAt ?? now, session: session ? dto : nil, restEnd: restEnd,
                         restTotalSeconds: restEnd == nil ? nil : 90, settings: SyncSettings(weightStep: step, accentRaw: accent))
    }

    private func envelope(_ state: SyncState) -> Envelope { SyncCodec.stateEnvelope(state)! }

    private func setA(_ remote: ConnectivityWorkoutRemote) -> SetEntryDTO? { remote.session?.exercises.first?.sets.first { $0.id == setA } }

    // MARK: - Apertura e stato salvato (punto 4)

    func testStartActivatesAndAsksStateWhenReachable() {
        transport.stateReply = envelope(state(revision: 10))
        let remote = makeRemote()
        remote.start()
        XCTAssertEqual(transport.activateCount, 1)
        XCTAssertTrue(transport.delegate === remote)
        XCTAssertEqual(transport.messages.compactMap(SyncCodec.kind), [.requestState])
        XCTAssertEqual(remote.session?.id, sessionID, "risposta dell'iPhone applicata")
        XCTAssertEqual(remote.connection, .live)
    }

    func testUnreachablePhoneUsesSavedStateWithoutAsking() {
        let first = makeRemote()
        first.apply(state(revision: 5, completedA: true))
        // App riaperta con l'iPhone non raggiungibile: nessuna richiesta, ultimo stato salvato.
        transport.isReachable = false
        let reopened = makeRemote()
        reopened.start()
        XCTAssertTrue(transport.messages.isEmpty)
        XCTAssertEqual(reopened.session?.id, sessionID)
        XCTAssertNotNil(setA(reopened)?.completedAt)
        XCTAssertEqual(reopened.connection, .offline(lastUpdate: now))
    }

    func testSavedStateOlderThanTwelveHoursIsDiscarded() {
        makeRemote().apply(state(revision: 5, sentAt: now))
        now = now.addingTimeInterval(SyncLimits.savedStateLifetime + 60)
        transport.isReachable = false
        let reopened = makeRemote()
        reopened.start()
        XCTAssertNil(reopened.session, "oltre 12 ore non si mostra più")
        XCTAssertNil(defaults.data(forKey: ConnectivityWorkoutRemote.savedStateKey))
    }

    func testSessionEndedStateClearsEverythingImmediately() {
        let remote = makeRemote()
        remote.apply(state(revision: 5))
        XCTAssertNotNil(defaults.data(forKey: ConnectivityWorkoutRemote.savedStateKey))
        remote.apply(state(revision: 6, session: false))
        XCTAssertNil(remote.session)
        XCTAssertNil(defaults.data(forKey: ConnectivityWorkoutRemote.savedStateKey), "l'iPhone ha detto che è finita: via anche lo stato salvato")
        let reopened = makeRemote()
        reopened.start()
        XCTAssertNil(reopened.session)
    }

    // MARK: - Revisioni e impostazioni

    func testOlderRevisionsAreDiscardedAndNewerWin() {
        let remote = makeRemote()
        remote.apply(state(revision: 100, weightA: 60))
        remote.apply(state(revision: 99, weightA: 10))
        XCTAssertEqual(setA(remote)?.weightKg, 60, "revisione più bassa: scartata")
        remote.apply(state(revision: 100, weightA: 10))
        XCTAssertEqual(setA(remote)?.weightKg, 60, "stessa revisione: scartata")
        remote.apply(state(revision: 101, weightA: 70))
        XCTAssertEqual(setA(remote)?.weightKg, 70)
    }

    func testReceivingStatesNeverSendsCommands() {
        // Nessun ciclo possibile sul Watch: ricevere stati (anche con recupero) non genera invii di comandi.
        let remote = makeRemote()
        for revision in 1...20 {
            remote.apply(state(revision: Int64(revision), restEnd: now.addingTimeInterval(30)))
        }
        remote.apply(state(revision: 21, session: false))
        XCTAssertTrue(transport.sentCommands.isEmpty)
        XCTAssertTrue(transport.queuedCommands.isEmpty)
    }

    func testSettingsComeFromTheState() {
        let remote = makeRemote()
        XCTAssertEqual(remote.weightStep, 2.5)
        XCTAssertEqual(remote.accent, .volt)
        remote.apply(state(revision: 1, step: 5, accent: "blu"))
        XCTAssertEqual(remote.weightStep, 5)
        XCTAssertEqual(remote.accent, .blu)
        remote.apply(state(revision: 2, accent: "colore-sconosciuto"))
        XCTAssertEqual(remote.accent, .volt, "accento sconosciuto: predefinito")
    }

    func testConnectionFollowsReachability() {
        let remote = makeRemote()
        remote.apply(state(revision: 1))
        XCTAssertEqual(remote.connection, .live)
        transport.isReachable = false
        remote.transportDidChange()
        XCTAssertEqual(remote.connection, .offline(lastUpdate: now))
        transport.isReachable = true
        transport.stateReply = envelope(state(revision: 2))
        remote.transportDidChange()
        XCTAssertEqual(remote.connection, .live)
        XCTAssertEqual(transport.messages.compactMap(SyncCodec.kind), [.requestState], "tornato raggiungibile: chiede lo stato")
    }

    // MARK: - Comandi

    func testCompleteSetSendsPreciseCommandAndShowsItOptimistically() throws {
        let remote = makeRemote()
        remote.apply(state(revision: 1))
        remote.completeSet(setB, of: exerciseID, at: now)
        let command = try XCTUnwrap(transport.sentCommands.first)
        XCTAssertEqual(command.sessionID, sessionID)
        XCTAssertEqual(command.sentAt, now)
        XCTAssertEqual(command.action, .completeSet(setID: setB, exerciseID: exerciseID))
        XCTAssertNotNil(remote.session?.exercises[0].sets[1].completedAt, "subito visibile sul Watch")
        XCTAssertTrue(transport.userInfos.isEmpty)
    }

    func testOptimisticChangeSurvivesStaleStateUntilReflected() {
        let remote = makeRemote()
        remote.apply(state(revision: 1))
        remote.completeSet(setA, of: exerciseID, at: now)
        // Stato dell'iPhone costruito prima di applicare il comando: la serie non deve "tornare indietro".
        remote.apply(state(revision: 2, completedA: false, sentAt: now.addingTimeInterval(-1)))
        XCTAssertNotNil(setA(remote)?.completedAt)
        // Stato che la riflette: il comando in sospeso decade e resta completata.
        remote.apply(state(revision: 3, completedA: true, sentAt: now.addingTimeInterval(1)))
        XCTAssertNotNil(setA(remote)?.completedAt)
        remote.apply(state(revision: 4, completedA: false, sentAt: now.addingTimeInterval(2)))
        XCTAssertNil(setA(remote)?.completedAt, "dopo il decadimento vale solo ciò che dice l'iPhone")
    }

    func testValuesAreAbsoluteAndOptimistic() throws {
        let remote = makeRemote()
        remote.apply(state(revision: 1))
        remote.setValues(of: setA, of: exerciseID, weightKg: 62.5, reps: nil)
        XCTAssertEqual(setA(remote)?.weightKg, 62.5)
        let command = try XCTUnwrap(transport.sentCommands.first)
        XCTAssertEqual(command.action, .setValues(setID: setA, exerciseID: exerciseID, weightKg: 62.5, reps: nil))
    }

    func testUnreachablePhoneQueuesSetCommandsButNotRestOnes() {
        let remote = makeRemote()
        remote.apply(state(revision: 1))
        transport.isReachable = false
        remote.completeSet(setA, of: exerciseID, at: now)
        remote.setValues(of: setB, of: exerciseID, weightKg: 55, reps: nil)
        remote.setRestEnd(endDate: now.addingTimeInterval(60), totalSeconds: 60)
        remote.skipRest()
        XCTAssertTrue(transport.messages.isEmpty)
        XCTAssertEqual(transport.queuedCommands.count, 2, "serie e valori in coda (transferUserInfo)")
        XCTAssertEqual(transport.queuedCommands.map(\.action), [
            .completeSet(setID: setA, exerciseID: exerciseID),
            .setValues(setID: setB, exerciseID: exerciseID, weightKg: 55, reps: nil)
        ])
        XCTAssertNotNil(setA(remote)?.completedAt, "intanto il Watch mostra l'effetto")
    }

    func testFailedSendFallsBackToQueueOnlyForSetCommands() {
        let remote = makeRemote()
        remote.apply(state(revision: 1))
        transport.failSends = true
        remote.completeSet(setA, of: exerciseID, at: now)
        remote.skipRest()
        XCTAssertEqual(transport.queuedCommands.count, 1)
        XCTAssertEqual(transport.queuedCommands.first?.action, .completeSet(setID: setA, exerciseID: exerciseID))
    }

    func testNoCommandsWithoutASession() {
        let remote = makeRemote()
        remote.completeSet(setA, of: exerciseID, at: now)
        XCTAssertTrue(transport.messages.isEmpty)
        XCTAssertTrue(transport.userInfos.isEmpty)
    }

    // MARK: - Recupero e avviso

    func testRestComesFromStateAndNotificationFollowsIt() {
        let remote = makeRemote()
        let end = now.addingTimeInterval(80)
        remote.apply(state(revision: 1, restEnd: end))
        XCTAssertEqual(remote.restState?.endDate, end)
        XCTAssertEqual(notifier.scheduled, [end], "recupero partito dall'iPhone: avviso al polso programmato")
        remote.apply(state(revision: 2, restEnd: end))
        XCTAssertEqual(notifier.scheduled.count, 1, "stessa scadenza: non si riprogramma")
        remote.apply(state(revision: 3, restEnd: end.addingTimeInterval(15)))
        XCTAssertEqual(notifier.scheduled.last, end.addingTimeInterval(15))
        remote.apply(state(revision: 4, restEnd: nil))
        XCTAssertEqual(notifier.cancelled, 1, "l'iPhone ha saltato il recupero: avviso annullato")
    }
}
