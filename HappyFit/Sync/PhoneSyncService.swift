import Foundation
import OSLog
import SwiftData

/// Aggancio con cui `ActiveWorkoutViewModel` avvisa il servizio quando il recupero parte, cambia o viene saltato.
/// Resta nil per impostazione predefinita: senza servizio il ViewModel si comporta come sempre.
@MainActor
protocol RestSyncing: AnyObject {
    func register(_ viewModel: ActiveWorkoutViewModel)
    func restChanged(endDate: Date?, totalSeconds: Int?)
}

/// Servizio iPhone della sincronizzazione col Watch. L'iPhone è l'unica fonte dei dati e l'unico che scrive in SwiftData:
/// applica i comandi del Watch tramite `WorkoutService` e pubblica lo stato della sessione aperta.
@MainActor
final class PhoneSyncService: ConnectivityTransportDelegate, RestSyncing {
    private let context: ModelContext
    private let workout: WorkoutService
    private let transport: any ConnectivityTransport
    private let defaults: UserDefaults
    private let clock: RevisionClock
    private let now: () -> Date
    private let minInterval: TimeInterval
    private let log = Logger(subsystem: "com.csince90.happyfit", category: "sync")

    private weak var activeViewModel: ActiveWorkoutViewModel?
    private var restEnd: Date?
    private var restTotal: Int?
    private var appliedOrder: [UUID] = []
    private var appliedSet: Set<UUID> = []
    private var lastPublish = Date.distantPast
    private var trailing: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastTransportPublish = Date.distantPast
    private var lastSentState: SyncState?
    private(set) var skippedDuplicates = 0
    private var lastSettings: SyncSettings
    private var previousCache: (key: [UUID], value: [UUID: [SetEntryDTO]])?

    /// Ultimo stato costruito (per i test e la diagnosi).
    private(set) var lastState: SyncState?

    init(
        context: ModelContext,
        transport: any ConnectivityTransport,
        defaults: UserDefaults = .standard,
        clock: RevisionClock? = nil,
        now: @escaping () -> Date = Date.init,
        minInterval: TimeInterval = SyncLimits.minPublishInterval
    ) {
        self.context = context
        self.workout = WorkoutService(context: context)
        self.transport = transport
        self.defaults = defaults
        self.clock = clock ?? RevisionClock(defaults: defaults)
        self.now = now
        self.minInterval = minInterval
        self.lastSettings = Self.settings(from: defaults)
    }

    /// Attiva la sessione (da chiamare all'avvio dell'app, anche se parte in background) e comincia ad ascoltare.
    func start() {
        transport.delegate = self
        transport.activate()
        let center = NotificationCenter.default
        // Ogni salvataggio di SwiftData (iPhone o comando del Watch) ripubblica lo stato.
        observers.append(center.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.requestPublish("salvataggio") }
        })
        // Cambi di impostazioni (incremento peso, accento): si ripubblica solo se sono davvero cambiate.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let current = Self.settings(from: self.defaults)
                if current != self.lastSettings { self.requestPublish("impostazioni") }
            }
        })
        requestPublish("avvio")
    }

    // MARK: - RestSyncing (recupero avviato dall'iPhone)

    func register(_ viewModel: ActiveWorkoutViewModel) {
        activeViewModel = viewModel
        // Dopo "Riduci" la schermata si ricrea: riprende il recupero in corso, solo se la fine è ancora futura.
        if let end = restEnd, let total = restTotal, end > now() {
            viewModel.applyRemoteRest(endDate: end, totalSeconds: total)
        }
    }

    func restChanged(endDate: Date?, totalSeconds: Int?) {
        restEnd = endDate
        restTotal = totalSeconds
        requestPublish("recupero")
    }

    // MARK: - Pubblicazione dello stato

    /// Pubblica subito se è passato l'intervallo minimo, altrimenti programma un invio finale: l'ultimo stato non si perde mai.
    func requestPublish(_ reason: String = "richiesta") {
        let elapsed = now().timeIntervalSince(lastPublish)
        if elapsed >= minInterval {
            trailing?.cancel()
            trailing = nil
            publishNow(reason: reason)
        } else if trailing == nil {
            let wait = minInterval - elapsed
            trailing = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                self.trailing = nil
                self.publishNow(reason: reason)
            }
        }
    }

    func publishNow(reason: String = "diretta") {
        lastPublish = now()
        lastSettings = Self.settings(from: defaults)
        guard transport.isActivated else { return }
        let state = buildState()
        lastState = state
        // Contenuto identico all'ultimo inviato: niente invio (salvo un Watch appena raggiungibile, che va aggiornato).
        if reason != "trasporto", let last = lastSentState, state.hasSameContent(as: last) {
            skippedDuplicates += 1
            return
        }
        guard transport.canSendInBackground || transport.isReachable, let envelope = SyncCodec.stateEnvelope(state) else { return }
        if transport.canSendInBackground { transport.updateContext(envelope) }
        // Con il Watch raggiungibile si manda anche subito: il contesto può arrivare con qualche ritardo.
        if transport.isReachable { transport.sendMessage(envelope, reply: nil, failure: nil) }
        lastSentState = state
        log.notice("stato pubblicato (\(reason, privacy: .public)) rev=\(state.revision) sessione=\(state.session?.id.uuidString ?? "nessuna", privacy: .public)")
    }

    func buildState() -> SyncState {
        let open = (try? workout.openSession()) ?? nil
        var dto: WorkoutSessionDTO?
        if let open {
            let key = open.sortedExercises.compactMap { $0.exercise?.id }
            if let cache = previousCache, cache.key == key {
                // Lo storico "ultima volta" non cambia durante l'allenamento: si riusa quello già calcolato.
                var built = buildDTOWithoutHistory(open)
                built.previousSets = cache.value
                dto = built
            } else if let full = try? workout.makeDTO(for: open) {
                previousCache = (key, full.previousSets)
                dto = full
            }
        }
        var end = restEnd
        var total = restTotal
        if dto == nil || end == nil || end! <= now() { end = nil; total = nil }
        return SyncState(
            revision: clock.next(), sentAt: now(), session: dto,
            restEnd: end, restTotalSeconds: total, settings: Self.settings(from: defaults)
        )
    }

    private func buildDTOWithoutHistory(_ session: WorkoutSession) -> WorkoutSessionDTO {
        WorkoutSessionDTO(
            id: session.id, name: session.name, startedAt: session.startedAt, endedAt: session.endedAt,
            exercises: session.sortedExercises.compactMap { $0.toDTO() }, previousSets: [:]
        )
    }

    private static func settings(from defaults: UserDefaults) -> SyncSettings {
        SyncSettings(
            weightStep: AppSettings.weightStep(defaults),
            accentRaw: defaults.string(forKey: AppSettings.accentKey) ?? AccentPreset.default.rawValue
        )
    }

    // MARK: - Comandi dal Watch

    /// Applica un comando. Idempotente (id già visto = nessun effetto) e prudente: se sessione o serie non
    /// esistono, o la serie non corrisponde, il comando si ignora. Ritorna sempre vero perché non va ritentato.
    @discardableResult
    func handle(_ command: WatchCommand) -> Bool {
        guard remember(command.id) else {
            log.debug("comando duplicato ignorato \(command.id.uuidString, privacy: .public)")
            return true
        }
        guard let session = (try? workout.openSession()) ?? nil, session.id == command.sessionID else {
            log.debug("comando per una sessione non più aperta: ignorato")
            return true
        }
        switch command.action {
        case .completeSet(let setID, let exerciseID):
            guard let (item, entry) = locate(setID, exerciseID, in: session), !entry.isCompleted else { return true }
            // completedAt = orario d'invio del comando, non quello di applicazione.
            try? workout.completeSet(entry, at: command.sentAt)
            let seconds = item.restSeconds
            let end = command.sentAt.addingTimeInterval(TimeInterval(seconds))
            // Un comando arrivato quando il recupero sarebbe già scaduto non ne avvia uno.
            if seconds > 0, end > now() {
                setRest(endDate: end, totalSeconds: seconds)
            }
        case .setValues(let setID, let exerciseID, let weightKg, let reps):
            guard let (_, entry) = locate(setID, exerciseID, in: session) else { return true }
            try? workout.updateSet(entry, weightKg: weightKg, reps: reps)
        case .setRestEnd(let endDate, let totalSeconds):
            setRest(endDate: endDate > now() ? endDate : nil, totalSeconds: endDate > now() ? totalSeconds : nil)
        case .skipRest:
            setRest(endDate: nil, totalSeconds: nil)
        }
        log.notice("comando applicato \(command.id.uuidString, privacy: .public) inviato=\(command.sentAt.timeIntervalSince1970, privacy: .public) applicato=\(Date().timeIntervalSince1970, privacy: .public)")
        requestPublish("comando")
        return true
    }

    private func setRest(endDate: Date?, totalSeconds: Int?) {
        restEnd = endDate
        restTotal = totalSeconds
        // Se la schermata della sessione è aperta sull'iPhone mostra lo stesso recupero (senza eco verso il servizio).
        activeViewModel?.applyRemoteRest(endDate: endDate, totalSeconds: totalSeconds)
    }

    private func locate(_ setID: UUID, _ exerciseID: UUID, in session: WorkoutSession) -> (SessionExercise, SetEntry)? {
        guard let item = session.exercises.first(where: { $0.id == exerciseID }),
              let entry = item.sets.first(where: { $0.id == setID }) else { return nil }
        return (item, entry)
    }

    /// Vero se l'id è nuovo (e lo ricorda, fino a un massimo), falso se già visto.
    private func remember(_ id: UUID) -> Bool {
        guard !appliedSet.contains(id) else { return false }
        appliedSet.insert(id)
        appliedOrder.append(id)
        if appliedOrder.count > SyncLimits.rememberedCommands {
            appliedSet.remove(appliedOrder.removeFirst())
        }
        return true
    }

    // MARK: - ConnectivityTransportDelegate

    func transportDidChange() {
        // Un Watch appena raggiungibile (o abbinato) riceve subito lo stato.
        log.notice("trasporto cambiato: attivo=\(self.transport.isActivated, privacy: .public) raggiungibile=\(self.transport.isReachable, privacy: .public)")
        // Un collegamento che oscilla (per esempio mentre le app si stabilizzano) non deve far partire un invio a ogni oscillazione.
        guard transport.isActivated, now().timeIntervalSince(lastTransportPublish) >= SyncLimits.transportPublishCooldown else { return }
        lastTransportPublish = now()
        publishNow(reason: "trasporto")
    }

    func transport(didReceiveMessage message: Envelope, reply: @escaping (Envelope) -> Void) {
        switch SyncCodec.kind(of: message) {
        case .command:
            if let command = SyncCodec.decodeCommand(message) {
                handle(command)
                reply(SyncCodec.ackEnvelope(for: command.id))
            } else {
                reply(Envelope(value: [:]))
            }
        case .requestState:
            if let envelope = SyncCodec.stateEnvelope(buildState()) {
                lastPublish = now()
                reply(envelope)
            } else {
                reply(Envelope(value: [:]))
            }
        default:
            reply(Envelope(value: [:]))
        }
    }

    func transport(didReceiveContext context: Envelope) {}

    /// Comandi accodati dal Watch quando l'iPhone non era raggiungibile (`transferUserInfo`).
    func transport(didReceiveUserInfo userInfo: Envelope) {
        if SyncCodec.kind(of: userInfo) == .command, let command = SyncCodec.decodeCommand(userInfo) {
            handle(command)
        }
    }
}
