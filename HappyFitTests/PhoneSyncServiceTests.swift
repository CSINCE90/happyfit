import XCTest
import SwiftData
@testable import HappyFit

/// Trasporto finto: registra ciò che il servizio invia, senza WCSession.
@MainActor
final class FakeTransport: ConnectivityTransport {
    weak var delegate: ConnectivityTransportDelegate?
    var isActivated = true
    var isReachable = true
    var canSendInBackground = true
    var receivedContext: Envelope?
    private(set) var activateCount = 0
    private(set) var contexts: [Envelope] = []
    private(set) var messages: [Envelope] = []
    private(set) var userInfos: [Envelope] = []

    func activate() { activateCount += 1 }
    func sendMessage(_ message: Envelope, reply: ((Envelope) -> Void)?, failure: ((Error) -> Void)?) { messages.append(message) }
    func updateContext(_ context: Envelope) { contexts.append(context) }
    func transferUserInfo(_ userInfo: Envelope) { userInfos.append(userInfo) }

    var lastContextState: SyncState? { contexts.last.flatMap(SyncCodec.decodeState) }
}

/// Test del servizio iPhone: applica i comandi del Watch e pubblica lo stato (SwiftData in memoria, trasporto finto).
@MainActor
final class PhoneSyncServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var workout: WorkoutService!
    private var transport: FakeTransport!
    private var defaults: UserDefaults!
    private var service: PhoneSyncService!
    private var panca: Exercise!
    private var squat: Exercise!
    private var session: WorkoutSession!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private var clockNow: Date!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        workout = WorkoutService(context: context)
        transport = FakeTransport()
        let suite = "phonesync-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        clockNow = base
        panca = try workout.createExercise(name: "Panca")
        squat = try workout.createExercise(name: "Squat")
        let template = try workout.createTemplate(name: "Push", exercises: [(panca, 3, 8, 90), (squat, 2, 5, 60)])
        session = try workout.startSession(from: template, at: base.addingTimeInterval(-600))
        service = makeService()
    }

    private func makeService(minInterval: TimeInterval = 0.05) -> PhoneSyncService {
        PhoneSyncService(
            context: context, transport: transport, defaults: defaults,
            clock: RevisionClock(defaults: defaults, now: { [unowned self] in clockNow }),
            now: { [unowned self] in clockNow }, minInterval: minInterval
        )
    }

    private func set(_ item: Int, _ index: Int) -> SetEntry { session.sortedExercises[item].sortedSets[index] }
    private func ids(_ item: Int, _ index: Int) -> (UUID, UUID) { (set(item, index).id, session.sortedExercises[item].id) }

    private func complete(_ item: Int, _ index: Int, sentAt: Date? = nil, id: UUID = UUID(), session sessionID: UUID? = nil) -> WatchCommand {
        let (setID, exerciseID) = ids(item, index)
        return WatchCommand(id: id, sessionID: sessionID ?? session.id, sentAt: sentAt ?? clockNow, action: .completeSet(setID: setID, exerciseID: exerciseID))
    }

    // MARK: - Comandi: completa serie

    func testCompleteSetUsesSentAtAndStartsRest() {
        let sent = base.addingTimeInterval(-5)
        service.handle(complete(0, 0, sentAt: sent))
        XCTAssertEqual(set(0, 0).completedAt, sent, "completedAt = orario d'invio, non quello di applicazione")
        let state = service.buildState()
        XCTAssertEqual(state.restEnd, sent.addingTimeInterval(90), "recupero dell'esercizio, dall'orario d'invio")
        XCTAssertEqual(state.restTotalSeconds, 90)
    }

    func testLateCompleteDoesNotStartRest() {
        // Il comando è partito 200 s fa: il recupero di 90 s sarebbe già scaduto.
        service.handle(complete(0, 0, sentAt: base.addingTimeInterval(-200)))
        XCTAssertTrue(set(0, 0).isCompleted)
        XCTAssertNil(service.buildState().restEnd)
    }

    func testRepeatedCommandHasNoEffect() {
        let command = complete(0, 0, sentAt: base.addingTimeInterval(-3))
        service.handle(command)
        let first = set(0, 0).completedAt
        // Stesso comando ripetuto più tardi (per esempio dopo un ritentativo): nessun effetto.
        clockNow = base.addingTimeInterval(30)
        service.handle(WatchCommand(id: command.id, sessionID: command.sessionID, sentAt: clockNow, action: command.action))
        XCTAssertEqual(set(0, 0).completedAt, first)
        XCTAssertEqual(session.completedSetCount, 1)
    }

    func testAlreadyCompletedSetIsNotCompletedAgain() {
        service.handle(complete(0, 0, sentAt: base.addingTimeInterval(-3)))
        let first = set(0, 0).completedAt
        // Comando diverso (altro id) sulla stessa serie: la serie resta com'è.
        service.handle(complete(0, 0, sentAt: base))
        XCTAssertEqual(set(0, 0).completedAt, first)
    }

    func testCommandNamesTheExactSetNeverTheNextOne() {
        // Il Watch indica la terza serie della panca: si completa quella, non la prima incompleta.
        service.handle(complete(0, 2))
        XCTAssertFalse(set(0, 0).isCompleted)
        XCTAssertFalse(set(0, 1).isCompleted)
        XCTAssertTrue(set(0, 2).isCompleted)
        // Esercizio sbagliato per quella serie: ignorato.
        let (setID, _) = ids(0, 0)
        service.handle(WatchCommand(sessionID: session.id, sentAt: clockNow, action: .completeSet(setID: setID, exerciseID: session.sortedExercises[1].id)))
        XCTAssertFalse(set(0, 0).isCompleted)
    }

    func testCommandsForMissingSessionOrSetAreIgnored() throws {
        service.handle(complete(0, 0, session: UUID()))
        XCTAssertEqual(session.completedSetCount, 0, "sessione diversa")
        service.handle(WatchCommand(sessionID: session.id, sentAt: clockNow, action: .completeSet(setID: UUID(), exerciseID: session.sortedExercises[0].id)))
        XCTAssertEqual(session.completedSetCount, 0, "serie inesistente")

        // Sessione chiusa: un comando in ritardo non fa nulla.
        let late = complete(1, 0, sentAt: base)
        try workout.completeSet(set(0, 0), at: base)
        try workout.finish(session, at: base.addingTimeInterval(10))
        service.handle(late)
        XCTAssertFalse(set(0, 0).isCompleted == false && session.completedSetCount > 1)
        XCTAssertEqual(session.completedSetCount, 1)
    }

    // MARK: - Comandi: valori e recupero

    func testSetValuesAreAbsoluteAndIdempotent() {
        let (setID, exerciseID) = ids(0, 1)
        service.handle(WatchCommand(sessionID: session.id, action: .setValues(setID: setID, exerciseID: exerciseID, weightKg: 60, reps: nil)))
        XCTAssertEqual(set(0, 1).weightKg, 60)
        XCTAssertEqual(set(0, 1).reps, 8, "reps invariate se nil")
        service.handle(WatchCommand(sessionID: session.id, action: .setValues(setID: setID, exerciseID: exerciseID, weightKg: nil, reps: 5)))
        XCTAssertEqual([set(0, 1).weightKg, Double(set(0, 1).reps)], [60, 5])
        // Altri valori assoluti (id diverso): l'ultimo comando arrivato vince.
        service.handle(WatchCommand(sessionID: session.id, action: .setValues(setID: setID, exerciseID: exerciseID, weightKg: 62.5, reps: 6)))
        XCTAssertEqual([set(0, 1).weightKg, Double(set(0, 1).reps)], [62.5, 6])
    }

    func testRestEndAndSkipCommands() {
        service.handle(WatchCommand(sessionID: session.id, action: .setRestEnd(endDate: base.addingTimeInterval(45), totalSeconds: 60)))
        XCTAssertEqual(service.buildState().restEnd, base.addingTimeInterval(45))
        XCTAssertEqual(service.buildState().restTotalSeconds, 60)
        // Fine già passata: nessun recupero.
        service.handle(WatchCommand(sessionID: session.id, action: .setRestEnd(endDate: base.addingTimeInterval(-1), totalSeconds: 60)))
        XCTAssertNil(service.buildState().restEnd)
        service.handle(WatchCommand(sessionID: session.id, action: .setRestEnd(endDate: base.addingTimeInterval(45), totalSeconds: 60)))
        service.handle(WatchCommand(sessionID: session.id, action: .skipRest))
        XCTAssertNil(service.buildState().restEnd)
    }

    // MARK: - Pubblicazione dello stato

    func testStateReflectsOpenSessionAndSettings() throws {
        defaults.set(5.0, forKey: AppSettings.weightStepKey)
        defaults.set("blu", forKey: AppSettings.accentKey)
        let state = service.buildState()
        XCTAssertEqual(state.session?.id, session.id)
        XCTAssertEqual(state.session?.exercises.count, 2)
        XCTAssertEqual(state.settings, SyncSettings(weightStep: 5, accentRaw: "blu"))
        try workout.discard(session)
        XCTAssertNil(service.buildState().session, "nessuna sessione aperta: stato vuoto")
        XCTAssertNil(service.buildState().restEnd)
    }

    func testSaveOnSameContextPublishesState() async throws {
        service.start()
        XCTAssertEqual(transport.activateCount, 1)
        XCTAssertTrue(transport.delegate === service)
        try await Task.sleep(for: .milliseconds(120))
        let before = transport.contexts.count
        try workout.completeSet(set(0, 0), at: base)   // come una modifica fatta dall'interfaccia dell'iPhone
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(transport.contexts.count, before, "il salvataggio ha fatto ripubblicare lo stato")
        XCTAssertEqual(transport.lastContextState?.session?.exercises[0].sets.filter { $0.completedAt != nil }.count, 1)
        XCTAssertGreaterThan(transport.messages.count, 0, "Watch raggiungibile: anche messaggio immediato")
    }

    func testThrottleAlwaysSendsFinalState() async throws {
        service.start()
        try await Task.sleep(for: .milliseconds(120))
        let before = transport.contexts.count
        // Raffica di modifiche dentro l'intervallo minimo (50 ms).
        for index in 0..<3 {
            try workout.completeSet(set(0, index), at: base)
        }
        try await Task.sleep(for: .milliseconds(250))
        let sent = transport.contexts.count - before
        XCTAssertGreaterThanOrEqual(sent, 1)
        XCTAssertLessThanOrEqual(sent, 3, "la raffica viene raggruppata")
        let last = transport.lastContextState
        XCTAssertEqual(last?.session?.exercises[0].sets.filter { $0.completedAt != nil }.count, 3, "l'ultimo stato non si perde")
    }

    func testRevisionsIncreaseAcrossRestarts() {
        let first = service.buildState().revision
        let second = service.buildState().revision
        XCTAssertGreaterThan(second, first)
        // Nuova istanza del servizio (app riavviata) con l'orologio tornato indietro: si continua a crescere.
        clockNow = base.addingTimeInterval(-3600)
        let restarted = makeService()
        XCTAssertGreaterThan(restarted.buildState().revision, second)
    }

    func testRequestStateIsAnsweredWithCurrentState() {
        var reply: Envelope?
        service.transport(didReceiveMessage: SyncCodec.requestStateEnvelope()) { reply = $0 }
        let state = reply.flatMap(SyncCodec.decodeState)
        XCTAssertEqual(state?.session?.id, session.id)
    }

    func testCommandMessageIsAcknowledgedAndUserInfoIsApplied() throws {
        let command = complete(0, 0)
        var reply: Envelope?
        service.transport(didReceiveMessage: try XCTUnwrap(SyncCodec.envelope(.command, command))) { reply = $0 }
        XCTAssertEqual(reply.flatMap(SyncCodec.ackID), command.id)
        XCTAssertTrue(set(0, 0).isCompleted)

        // Comando accodato dal Watch con transferUserInfo (iPhone prima non raggiungibile).
        let queued = complete(0, 1)
        service.transport(didReceiveUserInfo: try XCTUnwrap(SyncCodec.envelope(.command, queued)))
        XCTAssertTrue(set(0, 1).isCompleted)
        // Duplicato (messaggio e coda insieme): nessun effetto doppio.
        service.transport(didReceiveUserInfo: try XCTUnwrap(SyncCodec.envelope(.command, queued)))
        XCTAssertEqual(session.completedSetCount, 2)
    }

    // MARK: - Senza Watch

    func testWithoutWatchNothingIsSentAndNothingBreaks() {
        transport.canSendInBackground = false
        transport.isReachable = false
        service.start()
        service.publishNow()
        XCTAssertTrue(transport.contexts.isEmpty)
        XCTAssertTrue(transport.messages.isEmpty)
        // L'app funziona come prima: le modifiche locali non danno errori.
        XCTAssertNoThrow(try workout.completeSet(set(0, 0), at: base))
        transport.isActivated = false
        XCTAssertNoThrow(service.publishNow())
    }

    // MARK: - Aggancio nel ViewModel del recupero

    func testViewModelRestHookPublishesAndReceivesRemoteRest() throws {
        let defaultsForVM = UserDefaults(suiteName: "vm-\(UUID().uuidString)")!
        ActiveWorkoutViewModel.defaultRestSync = service
        defer { ActiveWorkoutViewModel.defaultRestSync = nil }
        let viewModel = ActiveWorkoutViewModel(session: session, context: context, defaults: defaultsForVM)
        XCTAssertNotNil(viewModel.restSync)

        // Recupero avviato sull'iPhone → finisce nello stato per il Watch.
        let real = Date()
        clockNow = real
        viewModel.startRest(seconds: 60, now: real)
        XCTAssertEqual(service.buildState().restEnd, real.addingTimeInterval(60))
        viewModel.addRest(seconds: 15, now: real)
        XCTAssertEqual(service.buildState().restEnd, real.addingTimeInterval(75))
        viewModel.skipRest()
        XCTAssertNil(service.buildState().restEnd)

        // Recupero avviato dal Watch → compare anche nella schermata dell'iPhone (senza eco verso il servizio).
        service.handle(WatchCommand(sessionID: session.id, sentAt: real, action: .setRestEnd(endDate: real.addingTimeInterval(40), totalSeconds: 60)))
        XCTAssertNotNil(viewModel.restTimer)
        XCTAssertEqual(viewModel.restTimer?.endDate, real.addingTimeInterval(40))
        service.handle(WatchCommand(sessionID: session.id, sentAt: real, action: .skipRest))
        XCTAssertNil(viewModel.restTimer)
        viewModel.skipRest()
    }

    func testViewModelWithoutServiceBehavesAsBefore() {
        XCTAssertNil(ActiveWorkoutViewModel.defaultRestSync, "i test non hanno servizio di sincronizzazione")
        let viewModel = ActiveWorkoutViewModel(session: session, context: context, defaults: UserDefaults(suiteName: "vm-\(UUID().uuidString)")!)
        XCTAssertNil(viewModel.restSync)
        viewModel.startRest(seconds: 30, now: base)
        XCTAssertNotNil(viewModel.restTimer)
        viewModel.skipRest()
        XCTAssertNil(viewModel.restTimer)
    }
}

/// Cambi di raggiungibilità ripetuti non devono far ripubblicare a raffica.
@MainActor
final class PhoneSyncTransportFlapTests: XCTestCase {
    func testFlappingReachabilityPublishesAtMostOncePerCooldown() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let transport = FakeTransport()
        var current = Date(timeIntervalSince1970: 1_700_000_000)
        let defaults = UserDefaults(suiteName: "flap-\(UUID().uuidString)")!
        let service = PhoneSyncService(
            context: container.mainContext, transport: transport, defaults: defaults,
            clock: RevisionClock(defaults: defaults, now: { current }), now: { current }
        )
        for _ in 0..<10 {
            service.transportDidChange()
            current = current.addingTimeInterval(0.2)   // 10 oscillazioni in 2 secondi
        }
        XCTAssertLessThanOrEqual(transport.contexts.count, 2, "oscillazioni raggruppate: \(transport.contexts.count) invii")
        XCTAssertGreaterThanOrEqual(transport.contexts.count, 1)
    }
}
