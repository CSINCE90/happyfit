import Foundation
import Observation
import SwiftData

/// Modifica di un allenamento concluso: nome, orari, serie ed esercizi.
@MainActor
@Observable
final class SessionDetailViewModel {
    let session: WorkoutSession
    private let service: WorkoutService

    var errorMessage: String?
    /// True quando l'utente ha tentato di togliere l'ultima serie completata: si propone di eliminare l'allenamento.
    var offerDeletingSession = false
    /// L'eliminazione dell'allenamento viene eseguita quando la schermata è già chiusa (vedi `performPendingDeletion`).
    private(set) var deletionPending = false

    init(session: WorkoutSession, context: ModelContext) {
        self.session = session
        self.service = WorkoutService(context: context)
    }

    @discardableResult
    func rename(to name: String) -> Bool {
        run { try service.renameSession(session, to: name) }
    }

    @discardableResult
    func updateTimes(start: Date, end: Date) -> Bool {
        run { try service.updateSessionTimes(session, startedAt: start, endedAt: end) }
    }

    @discardableResult
    func updateSet(_ entry: SetEntry, weightKg: Double, reps: Int, type: SetType) -> Bool {
        run { try service.updateSet(entry, weightKg: weightKg, reps: reps, type: type) }
    }

    func addSet(to item: SessionExercise) {
        let last = item.sortedSets.last
        run { try service.addCompletedSet(to: item, weightKg: last?.weightKg ?? 0, reps: last?.reps ?? 0) }
    }

    func removeSet(_ entry: SetEntry) {
        runOrOfferDeletion { try service.removeSetFromHistory(entry) }
    }

    func addExercise(_ exercise: Exercise) {
        run { try service.addExerciseToHistory(exercise, to: session) }
    }

    func removeExercise(_ item: SessionExercise) {
        runOrOfferDeletion { try service.removeExerciseFromHistory(item) }
    }

    /// Segna l'allenamento da eliminare: la vista si chiude e poi chiama `performPendingDeletion`.
    func requestSessionDeletion() {
        offerDeletingSession = false
        deletionPending = true
    }

    /// Elimina davvero l'allenamento (da chiamare quando la schermata non è più visibile).
    @discardableResult
    func performPendingDeletion() -> Bool {
        guard deletionPending else { return false }
        deletionPending = false
        return run { try service.deleteSession(session) }
    }

    @discardableResult
    private func run(_ work: () throws -> some Any) -> Bool {
        do {
            _ = try work()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func runOrOfferDeletion(_ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
        } catch WorkoutServiceError.sessionWouldBeEmpty {
            offerDeletingSession = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
