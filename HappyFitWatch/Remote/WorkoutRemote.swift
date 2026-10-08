import Foundation
import Observation

/// Il Watch è un telecomando della sessione avviata sull'iPhone: legge la sessione e invia pochi comandi.
/// Per ora c'è solo la realizzazione in memoria; nello step 5 arriverà quella con WatchConnectivity,
/// senza cambiare viste e ViewModel.
@MainActor
protocol WorkoutRemote: AnyObject {
    /// Sessione in corso sull'iPhone (nil = nessun allenamento avviato).
    var session: WorkoutSessionDTO? { get }
    func completeSet(_ setID: UUID, of exerciseID: UUID, at date: Date)
    func setValues(of setID: UUID, of exerciseID: UUID, weightKg: Double?, reps: Int?)
}

/// Sessione tenuta in memoria (dati di esempio o nessuna sessione).
@MainActor
@Observable
final class InMemoryWorkoutRemote: WorkoutRemote {
    private(set) var session: WorkoutSessionDTO?

    init(session: WorkoutSessionDTO?) {
        self.session = session
    }

    func completeSet(_ setID: UUID, of exerciseID: UUID, at date: Date) {
        guard let session else { return }
        self.session = SessionLogic.completingSet(setID, of: exerciseID, in: session, at: date)
    }

    func setValues(of setID: UUID, of exerciseID: UUID, weightKg: Double?, reps: Int?) {
        guard let session else { return }
        self.session = SessionLogic.settingValues(of: setID, of: exerciseID, in: session, weightKg: weightKg, reps: reps)
    }
}
