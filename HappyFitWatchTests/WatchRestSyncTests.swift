import XCTest
@testable import HappyFitWatch

/// Recupero: ViewModel del Watch + telecomando, con trasporto finto.
@MainActor
final class WatchRestSyncTests: XCTestCase {
    private var transport: FakeWatchTransport!
    private var notifications: FakeRestNotifications!
    private var remote: ConnectivityWorkoutRemote!
    private var viewModel: WatchSessionViewModel!
    private var now = Date(timeIntervalSince1970: 1_700_000_000)
    private let sessionID = UUID(), exerciseID = UUID(), setA = UUID(), setB = UUID()

    override func setUp() async throws {
        transport = FakeWatchTransport()
        notifications = FakeRestNotifications()
        notifications.notDetermined = false
        remote = ConnectivityWorkoutRemote(transport: transport, defaults: UserDefaults(suiteName: "rest-\(UUID().uuidString)")!, now: { [unowned self] in now })
        viewModel = WatchSessionViewModel(remote: remote, notifications: notifications, defaults: UserDefaults(suiteName: "vm-\(UUID().uuidString)")!)
        viewModel.onRestFinished = {}
        remote.apply(makeState(revision: 1))
    }

    private func makeState(revision: Int64, restEnd: Date? = nil, sentAt: Date? = nil) -> SyncState {
        let dto = WorkoutSessionDTO(
            id: sessionID, name: "Push", startedAt: now, endedAt: nil,
            exercises: [SessionExerciseDTO(id: exerciseID, exercise: ExerciseDTO(id: UUID(), name: "Panca"), order: 0, restSeconds: 90, sets: [
                SetEntryDTO(id: setA, order: 0, weightKg: 50, reps: 8, type: .normal, completedAt: nil),
                SetEntryDTO(id: setB, order: 1, weightKg: 50, reps: 8, type: .normal, completedAt: nil)
            ])],
            previousSets: [:]
        )
        return SyncState(revision: revision, sentAt: sentAt ?? now, session: dto, restEnd: restEnd, restTotalSeconds: restEnd == nil ? nil : 90,
                         settings: SyncSettings(weightStep: 5, accentRaw: "volt"))
    }

    func testWeightStepComesFromIPhoneSettings() {
        XCTAssertEqual(viewModel.weightStep, 5)
        viewModel.select(.weight)
        XCTAssertEqual(viewModel.crownStep, 5)
    }

    func testPlusMinusSendsAbsoluteEndAndSkipSendsSkip() throws {
        viewModel.startRest(seconds: 90, now: now)
        viewModel.addRest(seconds: 15, now: now)
        let command = try XCTUnwrap(transport.sentCommands.last)
        XCTAssertEqual(command.action, .setRestEnd(endDate: now.addingTimeInterval(105), totalSeconds: 105))
        viewModel.skipRest(now: now)
        XCTAssertEqual(transport.sentCommands.last?.action, .skipRest)
    }

    func testRestOfflineStaysLocalOnly() {
        transport.isReachable = false
        remote.transportDidChange()
        viewModel.startRest(seconds: 60, now: now)
        viewModel.addRest(seconds: 15, now: now)
        viewModel.skipRest(now: now)
        XCTAssertTrue(transport.messages.isEmpty)
        XCTAssertTrue(transport.userInfos.isEmpty, "i comandi sul recupero non si accodano")
        XCTAssertNil(viewModel.restTimer, "ma il timer locale ha funzionato")
    }

    func testNaturalFinishDoesNotSendACommand() {
        viewModel.startRest(seconds: 30, now: now)
        let before = transport.messages.count
        viewModel.tick(now: now.addingTimeInterval(31))
        XCTAssertNil(viewModel.restTimer)
        XCTAssertEqual(transport.messages.count, before)
    }

    func testRestStartedOnPhoneIsAdopted() {
        let end = now.addingTimeInterval(70)
        remote.apply(makeState(revision: 2, restEnd: end, sentAt: now.addingTimeInterval(1)))
        viewModel.adoptRemoteRest(now: now.addingTimeInterval(1))
        XCTAssertEqual(viewModel.restTimer?.endDate, end)
        XCTAssertEqual(viewModel.restTimer?.totalSeconds, 90)
        // ±15 dall'iPhone: nuova fine.
        remote.apply(makeState(revision: 3, restEnd: end.addingTimeInterval(15), sentAt: now.addingTimeInterval(2)))
        viewModel.adoptRemoteRest(now: now.addingTimeInterval(2))
        XCTAssertEqual(viewModel.restTimer?.endDate, end.addingTimeInterval(15))
        // Salto dall'iPhone (dopo il periodo di tolleranza): il timer si chiude.
        let later = now.addingTimeInterval(20)
        remote.apply(makeState(revision: 4, restEnd: nil, sentAt: later))
        viewModel.adoptRemoteRest(now: later)
        XCTAssertNil(viewModel.restTimer)
    }

    func testLocalRestIsNotClearedByAStaleStateRightAfterStarting() {
        viewModel.startRest(seconds: 90, now: now)
        // Stato dell'iPhone di un istante dopo ma ancora senza recupero (il comando non è arrivato): si ignora.
        let soon = now.addingTimeInterval(1)
        remote.apply(makeState(revision: 2, restEnd: nil, sentAt: soon))
        viewModel.adoptRemoteRest(now: soon)
        XCTAssertNotNil(viewModel.restTimer)
        // Uno stato PRECEDENTE alla modifica locale non conta mai.
        remote.apply(makeState(revision: 3, restEnd: now.addingTimeInterval(500), sentAt: now.addingTimeInterval(-5)))
        viewModel.adoptRemoteRest(now: soon)
        XCTAssertEqual(viewModel.restTimer?.endDate, now.addingTimeInterval(90))
    }

    func testPhoneStateWithTheSameEndDoesNotRestartTheLocalTimer() {
        viewModel.startRest(seconds: 90, now: now)
        let end = now.addingTimeInterval(90)
        remote.apply(makeState(revision: 2, restEnd: end, sentAt: now.addingTimeInterval(1)))
        viewModel.adoptRemoteRest(now: now.addingTimeInterval(1))
        XCTAssertEqual(viewModel.restTimer?.endDate, end)
        XCTAssertEqual(notifications.scheduled.count, 0, "nessuna riprogrammazione doppia dal ViewModel")
    }
}
