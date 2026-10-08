import Foundation
import Observation
import SwiftData
import UIKit

/// Logica della sessione di allenamento in corso (timer di recupero incluso).
@MainActor
@Observable
final class ActiveWorkoutViewModel {
    let session: WorkoutSession
    private let service: WorkoutService
    private let defaults: UserDefaults

    /// Timer di recupero attivo, se c'è.
    private(set) var restTimer: RestTimer?
    private(set) var restRemainingSeconds = 0
    /// Serie completate dell'ultima volta, per id esercizio.
    private(set) var previousSets: [UUID: [SetEntryDTO]] = [:]
    var errorMessage: String?
    /// Diventa true quando la sessione è stata chiusa o scartata: la vista si chiude.
    private(set) var didEnd = false

    /// Chiamata a fine recupero (di default vibrazione aptica).
    var onRestFinished: () -> Void = {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var tickTask: Task<Void, Never>?

    /// Aggancio opzionale alla sincronizzazione del recupero con il Watch. Nil per impostazione predefinita:
    /// senza servizio (test, anteprime, nessun Watch) il comportamento è quello di sempre.
    weak var restSync: (any RestSyncing)?
    /// Servizio che l'app imposta all'avvio; resta nil nei test.
    static var defaultRestSync: (any RestSyncing)?

    init(session: WorkoutSession, context: ModelContext, defaults: UserDefaults = .standard) {
        self.session = session
        self.service = WorkoutService(context: context)
        self.defaults = defaults
        reloadPrevious()
        restSync = Self.defaultRestSync
        restSync?.register(self)
    }

    var weightStep: Double { AppSettings.weightStep(defaults) }
    var completedSetCount: Int { session.completedSetCount }
    var incompleteSetCount: Int { session.incompleteSetCount }
    var canDiscard: Bool { completedSetCount == 0 }

    // MARK: - Valori dell'ultima volta

    func previousSummary(for item: SessionExercise) -> String? {
        guard let id = item.exercise?.id, let sets = previousSets[id], !sets.isEmpty else { return nil }
        return sets.map { Formatting.setSummary(weightKg: $0.weightKg, reps: $0.reps) }.joined(separator: " · ")
    }

    private func reloadPrevious() {
        previousSets = (try? service.makeDTO(for: session).previousSets) ?? [:]
    }

    // MARK: - Serie

    /// Spunta o toglie la spunta; completando una serie parte il recupero dell'esercizio.
    func toggleComplete(_ entry: SetEntry, now: Date = Date()) {
        perform {
            if entry.isCompleted {
                try service.uncompleteSet(entry)
            } else {
                try service.completeSet(entry, at: now)
                if let item = entry.sessionExercise { startRest(seconds: item.restSeconds, now: now) }
            }
        }
    }

    func adjustWeight(_ entry: SetEntry, direction: Int) {
        let value = entry.weightKg + Double(direction) * weightStep
        setWeight(entry, (max(value, 0) * 100).rounded() / 100)
    }

    func adjustReps(_ entry: SetEntry, delta: Int) {
        setReps(entry, entry.reps + delta)
    }

    func setWeight(_ entry: SetEntry, _ value: Double) {
        perform { try service.updateSet(entry, weightKg: value) }
    }

    func setReps(_ entry: SetEntry, _ value: Int) {
        perform { try service.updateSet(entry, reps: value) }
    }

    func setType(_ entry: SetEntry, _ type: SetType) {
        perform { try service.updateSet(entry, type: type) }
    }

    func addSet(to item: SessionExercise) {
        perform { try service.addSet(to: item) }
    }

    func removeSet(_ entry: SetEntry) {
        perform { try service.removeSet(entry) }
    }

    // MARK: - Esercizi

    func addExercise(_ exercise: Exercise) {
        perform {
            try service.addExercise(exercise, to: session, restSeconds: exercise.defaultRestSeconds ?? AppSettings.defaultRestSeconds(defaults))
            reloadPrevious()
        }
    }

    func removeExercise(_ item: SessionExercise) {
        perform { try service.removeSessionExercise(item) }
    }

    /// Cambia il recupero dell'esercizio solo in questa sessione.
    func setRest(_ item: SessionExercise, seconds: Int) {
        perform { try service.updateRest(item, seconds: seconds) }
    }

    func rename(to name: String) {
        perform { try service.renameSession(session, to: name) }
    }

    // MARK: - Chiusura

    /// Chiude tenendo solo le serie completate. Ritorna false (con errorMessage) se non è possibile.
    @discardableResult
    func finish(at date: Date = Date()) -> Bool {
        let ok = perform { try service.finish(session, at: date) }
        if ok { end() }
        return ok
    }

    @discardableResult
    func discard() -> Bool {
        let ok = perform { try service.discard(session) }
        if ok { end() }
        return ok
    }

    private func end() {
        skipRest()
        didEnd = true
    }

    // MARK: - Timer di recupero

    func startRest(seconds: Int, now: Date = Date()) {
        guard seconds > 0 else { return skipRest() }
        restTimer = RestTimer(seconds: seconds, now: now)
        restRemainingSeconds = seconds
        startTicking()
        restSync?.restChanged(endDate: restTimer?.endDate, totalSeconds: restTimer?.totalSeconds)
    }

    func skipRest() {
        restTimer = nil
        restRemainingSeconds = 0
        tickTask?.cancel()
        tickTask = nil
        restSync?.restChanged(endDate: nil, totalSeconds: nil)
    }

    /// Recupero avviato, cambiato o saltato dal Watch: stesso timer, senza riavvisare il servizio (niente eco).
    func applyRemoteRest(endDate: Date?, totalSeconds: Int?, now: Date = Date()) {
        guard let endDate, let totalSeconds, endDate > now else {
            restTimer = nil
            restRemainingSeconds = 0
            tickTask?.cancel()
            tickTask = nil
            return
        }
        let timer = RestTimer(seconds: totalSeconds, now: endDate.addingTimeInterval(-TimeInterval(totalSeconds)))
        restTimer = timer
        restRemainingSeconds = timer.remainingSeconds(at: now)
        startTicking()
    }

    func addRest(seconds: Int, now: Date = Date()) {
        guard var timer = restTimer else { return startRest(seconds: max(seconds, 0), now: now) }
        timer.add(seconds: seconds)
        restTimer = timer
        tick(now: now)
        restSync?.restChanged(endDate: restTimer?.endDate, totalSeconds: restTimer?.totalSeconds)
    }

    /// Aggiorna il conto alla rovescia; a zero vibra e chiude il timer.
    func tick(now: Date = Date()) {
        guard let timer = restTimer else { return }
        if timer.isFinished(at: now) {
            skipRest()
            onRestFinished()
        } else {
            restRemainingSeconds = timer.remainingSeconds(at: now)
        }
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

    // MARK: - Interni

    @discardableResult
    private func perform(_ work: () throws -> some Any) -> Bool {
        do {
            _ = try work()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        do {
            try work()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
