import Foundation
import Observation
import WatchKit

/// Stato dell'app Watch: quale serie mostrare, valore cambiato dalla Digital Crown, timer di recupero.
/// Agisce solo tramite `WorkoutRemote` (la sessione vive sull'iPhone) e la logica pura di `SessionLogic`.
@MainActor
@Observable
final class WatchSessionViewModel {
    enum Field: Equatable { case weight, reps }

    enum Screen: Equatable {
        case noSession
        case allDone
        case set(SetPosition)
    }

    let remote: any WorkoutRemote
    private let notifications: any RestNotificationScheduling
    private let defaults: UserDefaults

    /// Incremento del peso della Crown: lo sceglie l'utente sull'iPhone (2,5 kg finché non arriva una scelta).
    var weightStep: Double { remote.weightStep }
    var repsStep: Int = 1

    /// Esercizio scelto dall'elenco (nil = quello corrente).
    private(set) var shownExerciseID: UUID?
    /// Valore che la Crown sta cambiando (nil = nessuno).
    private(set) var selectedField: Field?

    private(set) var restTimer: RestTimer?
    private(set) var restRemainingSeconds = 0
    /// Spiegazione mostrata prima della richiesta di sistema per le notifiche (solo la prima volta).
    var showPermissionExplanation = false
    /// Programmazione dell'avviso in corso (esposta per i test).
    private(set) var notificationTask: Task<Void, Never>?

    /// A fine recupero con l'app in primo piano: vibrazione.
    var onRestFinished: () -> Void = { WKInterfaceDevice.current().play(.notification) }

    static let permissionExplainedKey = "restNotificationExplained"
    private var tickTask: Task<Void, Never>?
    private var restExerciseName: String?
    /// Ultima modifica del recupero fatta qui: lo stato dell'iPhone vale solo se è successivo.
    private var localRestChangedAt = Date.distantPast
    /// Dopo una modifica locale, uno stato dell'iPhone "senza recupero" nei primi secondi può essere solo in ritardo.
    static let remoteRestGrace: TimeInterval = 5

    init(remote: any WorkoutRemote, notifications: any RestNotificationScheduling, defaults: UserDefaults = .standard) {
        self.remote = remote
        self.notifications = notifications
        self.defaults = defaults
    }

    // MARK: - Cosa mostrare

    var screen: Screen {
        guard let session = remote.session else { return .noSession }
        guard let position = SessionLogic.displayed(in: session, preferredExerciseID: shownExerciseID) else { return .allDone }
        return .set(position)
    }

    var exercises: [SessionExerciseDTO] {
        remote.session.map(SessionLogic.orderedExercises) ?? []
    }

    var shownExercise: SessionExerciseDTO? {
        guard case .set(let position) = screen else { return nil }
        return exercises[position.exerciseIndex]
    }

    var shownSet: SetEntryDTO? {
        guard case .set(let position) = screen, let exercise = shownExercise else { return nil }
        return SessionLogic.orderedSets(exercise)[position.setIndex]
    }

    /// "Serie 2 di 4"
    var setLabel: String {
        guard case .set(let position) = screen, let exercise = shownExercise else { return "" }
        return "Serie \(position.setIndex + 1) di \(exercise.sets.count)"
    }

    /// "Ultima volta: 52,5 × 8" (nil senza storico: la riga si nasconde).
    var previousSummary: String? {
        guard case .set(let position) = screen, let session = remote.session, let exercise = shownExercise,
              let previous = SessionLogic.previousSet(in: session, exercise: exercise, setIndex: position.setIndex) else { return nil }
        return "Ultima volta: \(Self.weightText(previous.weightKg)) × \(previous.reps)"
    }

    /// "1:30"
    static func clockText(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(seconds, 0) / 60, max(seconds, 0) % 60)
    }

    static func weightText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Sceglie dall'elenco quale esercizio mostrare (i dati non cambiano).
    func show(exerciseID: UUID) {
        shownExerciseID = exerciseID
        selectedField = nil
    }

    // MARK: - Digital Crown

    /// Tocco su peso o ripetizioni: lo seleziona (un secondo tocco lo deseleziona).
    func select(_ field: Field) {
        selectedField = selectedField == field ? nil : field
    }

    var crownRange: ClosedRange<Double> {
        selectedField == .reps ? 0...Double(SessionLogic.maxReps) : 0...SessionLogic.maxWeightKg
    }

    var crownStep: Double {
        selectedField == .reps ? Double(repsStep) : weightStep
    }

    /// Valore collegato alla Crown: legge e scrive peso o ripetizioni della serie mostrata.
    var crownValue: Double {
        get {
            guard let set = shownSet else { return 0 }
            return selectedField == .reps ? Double(set.reps) : set.weightKg
        }
        set {
            guard let field = selectedField, let set = shownSet, let exercise = shownExercise else { return }
            switch field {
            case .weight:
                let snapped = (newValue / weightStep).rounded() * weightStep
                guard snapped != set.weightKg else { return }
                remote.setValues(of: set.id, of: exercise.id, weightKg: snapped, reps: nil)
            case .reps:
                let reps = Int(newValue.rounded())
                guard reps != set.reps else { return }
                remote.setValues(of: set.id, of: exercise.id, weightKg: nil, reps: reps)
            }
        }
    }

    // MARK: - Completa serie

    /// Completa la prima serie incompleta dell'esercizio mostrato e avvia il recupero.
    /// Se l'esercizio è finito si passa da soli al primo con serie incomplete.
    func completeShownSet(now: Date = Date()) {
        guard let exercise = shownExercise, let set = shownSet else { return }
        remote.completeSet(set.id, of: exercise.id, at: now)
        selectedField = nil
        if let updated = remote.session?.exercises.first(where: { $0.id == exercise.id }),
           SessionLogic.firstIncompleteSetIndex(updated) == nil {
            shownExerciseID = nil
        }
        // Nessuna serie da fare dopo: niente recupero.
        guard screen != .allDone else { return skipRest() }
        startRest(seconds: exercise.restSeconds, now: now)
    }

    // MARK: - Timer di recupero

    /// Avvia il recupero in locale. L'iPhone lo ricava da "completa serie" (stessa serie, stesso orario d'invio).
    func startRest(seconds: Int, now: Date = Date()) {
        guard seconds > 0 else { return skipRest() }
        localRestChangedAt = now
        restTimer = RestTimer(seconds: seconds, now: now)
        restRemainingSeconds = seconds
        restExerciseName = shownExercise?.exercise.name
        startTicking()
        notificationTask = Task { await prepareNotification() }
    }

    /// ±15 s: aggiorna il timer locale e comunica all'iPhone la nuova fine come orario assoluto (idempotente).
    func addRest(seconds: Int, now: Date = Date()) {
        guard var timer = restTimer else { return }
        timer.add(seconds: seconds)
        restTimer = timer
        localRestChangedAt = now
        tick(now: now)
        if let current = restTimer {
            notifications.schedule(at: current.endDate, exerciseName: restExerciseName)
            remote.setRestEnd(endDate: current.endDate, totalSeconds: current.totalSeconds)
        }
    }

    /// Salta il recupero: lo annulla qui (e l'avviso) e lo comunica all'iPhone.
    func skipRest(now: Date = Date()) {
        localRestChangedAt = now
        clearRestLocally()
        remote.skipRest()
    }

    private func clearRestLocally() {
        restTimer = nil
        restRemainingSeconds = 0
        tickTask?.cancel()
        tickTask = nil
        notifications.cancel()
    }

    /// Aggiorna il conto alla rovescia; a zero vibra (app in primo piano) e chiude il timer
    /// (a fine tempo l'iPhone ha già la stessa scadenza: nessun comando da inviare).
    func tick(now: Date = Date()) {
        guard let timer = restTimer else { return }
        if timer.isFinished(at: now) {
            clearRestLocally()
            onRestFinished()
        } else {
            restRemainingSeconds = timer.remainingSeconds(at: now)
        }
    }

    /// Recupero come lo comunica l'iPhone (partito da lì, o ±15 da lì): vale solo se lo stato è successivo
    /// all'ultima modifica fatta qui; uno stato "senza recupero" subito dopo una modifica locale si ignora.
    func adoptRemoteRest(now: Date = Date()) {
        guard let rest = remote.restState, rest.asOf > localRestChangedAt else { return }
        if let end = rest.endDate, let total = rest.totalSeconds, end > now {
            guard restTimer?.endDate != end else { return }
            restTimer = RestTimer(seconds: total, now: end.addingTimeInterval(-TimeInterval(total)))
            restRemainingSeconds = restTimer?.remainingSeconds(at: now) ?? 0
            restExerciseName = restExerciseName ?? shownExercise?.exercise.name
            startTicking()
        } else if restTimer != nil, now.timeIntervalSince(localRestChangedAt) > Self.remoteRestGrace {
            clearRestLocally()
        }
    }

    /// Cambia quando lo stato dell'iPhone cambia il recupero (la vista lo osserva per chiamare `adoptRemoteRest`).
    var remoteRestVersion: RemoteRest? { remote.restState }

    /// Risposta alla spiegazione: "Consenti" mostra la richiesta di sistema, "Non ora" resta solo la vibrazione in primo piano.
    func answerPermission(allow: Bool) async {
        defaults.set(true, forKey: Self.permissionExplainedKey)
        showPermissionExplanation = false
        if allow, await notifications.requestAuthorization(), let timer = restTimer {
            notifications.schedule(at: timer.endDate, exerciseName: restExerciseName)
        }
    }

    private func prepareNotification() async {
        if await notifications.needsAuthorization() {
            // Prima volta: spiegazione breve, poi la richiesta di sistema (vedi answerPermission).
            if !defaults.bool(forKey: Self.permissionExplainedKey) { showPermissionExplanation = true }
            return
        }
        guard let timer = restTimer else { return }
        notifications.schedule(at: timer.endDate, exerciseName: restExerciseName)
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.restTimer != nil else { return }
                self.tick()
            }
        }
    }
}
