import Foundation
import Observation
import OSLog

/// Telecomando reale: riceve lo stato dall'iPhone e gli invia i comandi con WatchConnectivity.
/// L'iPhone è l'unica fonte dei dati: qui si tiene l'ultimo stato accettato più i comandi non ancora riflessi (aggiornamento ottimistico).
@MainActor
@Observable
final class ConnectivityWorkoutRemote: WorkoutRemote, ConnectivityTransportDelegate {
    private(set) var session: WorkoutSessionDTO?
    private(set) var restState: RemoteRest?
    private(set) var weightStep: Double = 2.5
    private(set) var accent: AccentPreset = .default
    private(set) var reachable = false
    private(set) var lastUpdate: Date?

    var connection: RemoteConnection { reachable ? .live : .offline(lastUpdate: lastUpdate) }

    private struct Pending {
        var command: WatchCommand
        var ackedAt: Date?
    }

    @ObservationIgnored private let transport: any ConnectivityTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let restNotifier: (any RestNotificationScheduling)?
    @ObservationIgnored private let log = Logger(subsystem: "com.csince90.happyfit", category: "sync")
    @ObservationIgnored private var base: SyncState?
    @ObservationIgnored private var lastRevision: Int64 = 0
    @ObservationIgnored private var pending: [Pending] = []
    @ObservationIgnored private var lastScheduledEnd: Date?

    static let savedStateKey = "watchLastSyncState"
    /// Un comando accodato non ancora riflesso dopo tanto tempo si considera perso.
    static let pendingLifetime: TimeInterval = 600

    init(
        transport: any ConnectivityTransport,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        restNotifier: (any RestNotificationScheduling)? = nil
    ) {
        self.transport = transport
        self.defaults = defaults
        self.now = now
        self.restNotifier = restNotifier
    }

    /// Attiva la sessione (da chiamare all'avvio dell'app), carica l'ultimo stato noto e chiede quello attuale.
    func start() {
        transport.delegate = self
        transport.activate()
        loadSavedState()
        if let context = transport.receivedContext, let state = SyncCodec.decodeState(context) {
            apply(state)
        }
        requestState()
    }

    // MARK: - WorkoutRemote

    func requestState() {
        reachable = transport.isReachable
        // Stessa logica di raggiungibilità degli invii: se l'iPhone non è raggiungibile resta l'ultimo stato salvato.
        guard transport.isActivated, transport.isReachable else { return }
        transport.sendMessage(SyncCodec.requestStateEnvelope(), reply: { [weak self] envelope in
            if let state = SyncCodec.decodeState(envelope) { self?.apply(state) }
        }, failure: nil)
    }

    func completeSet(_ setID: UUID, of exerciseID: UUID, at date: Date) {
        send(.completeSet(setID: setID, exerciseID: exerciseID), at: date, optimistic: true)
    }

    func setValues(of setID: UUID, of exerciseID: UUID, weightKg: Double?, reps: Int?) {
        send(.setValues(setID: setID, exerciseID: exerciseID, weightKg: weightKg, reps: reps), at: now(), optimistic: true)
    }

    func setRestEnd(endDate: Date, totalSeconds: Int) {
        send(.setRestEnd(endDate: endDate, totalSeconds: totalSeconds), at: now(), optimistic: false)
    }

    func skipRest() {
        send(.skipRest, at: now(), optimistic: false)
    }

    // MARK: - Invio dei comandi

    private func send(_ action: WatchCommand.Action, at date: Date, optimistic: Bool) {
        guard let sessionID = base?.session?.id else { return }
        let command = WatchCommand(sessionID: sessionID, sentAt: date, action: action)
        if optimistic {
            pending.append(Pending(command: command))
            recomputeSession()
        }
        deliver(command)
    }

    private func deliver(_ command: WatchCommand) {
        guard let envelope = SyncCodec.envelope(.command, command) else { return }
        log.notice("comando inviato \(command.id.uuidString, privacy: .public) alle \(Date().timeIntervalSince1970, privacy: .public)")
        if transport.isReachable {
            transport.sendMessage(envelope, reply: { [weak self] reply in
                guard let self, SyncCodec.ackID(reply) == command.id else { return }
                self.markAcknowledged(command.id)
            }, failure: { [weak self] _ in
                // Raggiungibilità persa durante l'invio: i comandi sulla serie si accodano, quelli sul tempo no.
                if !command.isTimeSensitive { self?.transport.transferUserInfo(envelope) }
            })
        } else if !command.isTimeSensitive {
            // iPhone non raggiungibile: coda garantita e in ordine (i comandi sono idempotenti).
            transport.transferUserInfo(envelope)
        }
        // Comandi sul recupero con iPhone non raggiungibile: restano solo sul timer locale del Watch.
    }

    private func markAcknowledged(_ id: UUID) {
        if let index = pending.firstIndex(where: { $0.command.id == id }) {
            pending[index].ackedAt = now()
        }
    }

    // MARK: - Stato in arrivo

    func apply(_ state: SyncState) {
        guard state.revision > lastRevision else {
            log.debug("stato scartato (revisione vecchia) rev=\(state.revision)")
            return
        }
        lastRevision = state.revision
        base = state
        weightStep = state.settings.weightStep
        accent = AccentPreset(rawValue: state.settings.accentRaw) ?? .default
        lastUpdate = state.sentAt
        reachable = transport.isReachable

        let previousEnd = restState?.endDate
        restState = RemoteRest(endDate: state.restEnd, totalSeconds: state.restTotalSeconds, asOf: state.sentAt)

        if state.session == nil {
            // L'iPhone comunica che la sessione è finita: via lo stato salvato e i comandi in sospeso.
            pending.removeAll()
            defaults.removeObject(forKey: Self.savedStateKey)
        } else {
            prunePending(against: state)
            if let data = SyncCodec.data(state) { defaults.set(data, forKey: Self.savedStateKey) }
        }
        recomputeSession()
        updateRestNotification(newEnd: state.restEnd, previousEnd: previousEnd)
        log.notice("stato ricevuto rev=\(state.revision) inviato=\(state.sentAt.timeIntervalSince1970, privacy: .public) ricevuto=\(Date().timeIntervalSince1970, privacy: .public)")
    }

    /// Un comando non serve più quando lo stato lo riflette, la sessione è cambiata, è stato confermato prima di quello stato o è troppo vecchio.
    private func prunePending(against state: SyncState) {
        pending.removeAll { entry in
            guard let session = state.session, entry.command.sessionID == session.id else { return true }
            if let ackedAt = entry.ackedAt, state.sentAt >= ackedAt { return true }
            if now().timeIntervalSince(entry.command.sentAt) > Self.pendingLifetime { return true }
            return Self.isReflected(entry.command, in: session)
        }
    }

    private static func isReflected(_ command: WatchCommand, in session: WorkoutSessionDTO) -> Bool {
        switch command.action {
        case .completeSet(let setID, let exerciseID):
            return set(setID, exerciseID, in: session)?.completedAt != nil
        case .setValues(let setID, let exerciseID, let weightKg, let reps):
            guard let entry = set(setID, exerciseID, in: session) else { return true }
            return (weightKg == nil || entry.weightKg == min(max(weightKg!, 0), SessionLogic.maxWeightKg))
                && (reps == nil || entry.reps == min(max(reps!, 0), SessionLogic.maxReps))
        case .setRestEnd, .skipRest:
            return true
        }
    }

    private static func set(_ setID: UUID, _ exerciseID: UUID, in session: WorkoutSessionDTO) -> SetEntryDTO? {
        session.exercises.first { $0.id == exerciseID }?.sets.first { $0.id == setID }
    }

    /// Sessione mostrata: ultimo stato dell'iPhone più i comandi non ancora riflessi.
    private func recomputeSession() {
        guard var shown = base?.session else {
            session = nil
            return
        }
        for entry in pending {
            let command = entry.command
            guard command.sessionID == shown.id else { continue }
            switch command.action {
            case .completeSet(let setID, let exerciseID):
                if Self.set(setID, exerciseID, in: shown)?.completedAt == nil {
                    shown = SessionLogic.completingSet(setID, of: exerciseID, in: shown, at: command.sentAt)
                }
            case .setValues(let setID, let exerciseID, let weightKg, let reps):
                shown = SessionLogic.settingValues(of: setID, of: exerciseID, in: shown, weightKg: weightKg, reps: reps)
            case .setRestEnd, .skipRest:
                break
            }
        }
        session = shown
    }

    // MARK: - Avviso di fine recupero

    /// Con un recupero partito dall'iPhone (anche con l'app Watch in background) si programma l'avviso al polso;
    /// si annulla solo se l'iPhone comunica che il recupero è stato saltato.
    private func updateRestNotification(newEnd: Date?, previousEnd: Date?) {
        if let newEnd, newEnd > now() {
            if lastScheduledEnd != newEnd {
                lastScheduledEnd = newEnd
                restNotifier?.schedule(at: newEnd, exerciseName: nil)
            }
        } else if previousEnd != nil {
            lastScheduledEnd = nil
            restNotifier?.cancel()
        }
    }

    // MARK: - Stato salvato

    private func loadSavedState() {
        guard let data = defaults.data(forKey: Self.savedStateKey), let state = SyncCodec.state(from: data) else { return }
        // Dopo 12 ore l'ultimo stato noto non è più affidabile.
        guard now().timeIntervalSince(state.sentAt) < SyncLimits.savedStateLifetime else {
            defaults.removeObject(forKey: Self.savedStateKey)
            return
        }
        apply(state)
    }

    // MARK: - ConnectivityTransportDelegate

    func transportDidChange() {
        let wasReachable = reachable
        reachable = transport.isReachable
        log.notice("watch: collegamento cambiato attivo=\(self.transport.isActivated, privacy: .public) raggiungibile=\(self.transport.isReachable, privacy: .public)")
        // iPhone tornato raggiungibile: si chiede lo stato aggiornato.
        if reachable && !wasReachable { requestState() }
    }

    func transport(didReceiveMessage message: Envelope, reply: @escaping (Envelope) -> Void) {
        if let state = SyncCodec.decodeState(message) { apply(state) }
        reply(Envelope(value: [:]))
    }

    func transport(didReceiveContext context: Envelope) {
        if let state = SyncCodec.decodeState(context) { apply(state) }
    }

    func transport(didReceiveUserInfo userInfo: Envelope) {}
}
