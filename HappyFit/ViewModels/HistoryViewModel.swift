import Foundation
import Observation
import SwiftData

/// Storico: eliminazione di un allenamento e registrazione a posteriori.
@MainActor
@Observable
final class HistoryViewModel {
    private let service: WorkoutService
    var errorMessage: String?

    init(context: ModelContext) {
        self.service = WorkoutService(context: context)
    }

    @discardableResult
    func delete(_ session: WorkoutSession) -> Bool {
        do {
            try service.deleteSession(session)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createPast(name: String, startedAt: Date, endedAt: Date, exercise: Exercise, weightKg: Double, reps: Int) -> WorkoutSession? {
        do {
            errorMessage = nil
            return try service.createPastSession(name: name, startedAt: startedAt, endedAt: endedAt, exercise: exercise, weightKg: weightKg, reps: reps)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
