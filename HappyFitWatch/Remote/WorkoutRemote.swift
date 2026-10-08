import Foundation
import Observation

/// Recupero come lo comunica l'iPhone (orario assoluto), con l'istante dello stato da cui proviene.
struct RemoteRest: Equatable, Sendable {
    var endDate: Date?
    var totalSeconds: Int?
    /// Quando l'iPhone ha costruito lo stato che lo contiene.
    var asOf: Date
}

/// Stato del collegamento con l'iPhone.
enum RemoteConnection: Equatable, Sendable {
    case live
    /// iPhone non raggiungibile: si mostra l'ultimo stato noto, aggiornato a `lastUpdate`.
    case offline(lastUpdate: Date?)
}

/// Il Watch è un telecomando della sessione avviata sull'iPhone: legge la sessione e invia pochi comandi.
/// Realizzazioni: `ConnectivityWorkoutRemote` (WatchConnectivity) e `InMemoryWorkoutRemote` (Debug e anteprime).
@MainActor
protocol WorkoutRemote: AnyObject {
    /// Sessione in corso sull'iPhone (nil = nessun allenamento avviato).
    var session: WorkoutSessionDTO? { get }
    var restState: RemoteRest? { get }
    /// Incremento del peso scelto sull'iPhone.
    var weightStep: Double { get }
    var accent: AccentPreset { get }
    var connection: RemoteConnection { get }

    func completeSet(_ setID: UUID, of exerciseID: UUID, at date: Date)
    func setValues(of setID: UUID, of exerciseID: UUID, weightKg: Double?, reps: Int?)
    /// Cambia la fine del recupero (orario assoluto). Con l'iPhone non raggiungibile non viene inviato.
    func setRestEnd(endDate: Date, totalSeconds: Int)
    func skipRest()
    /// Chiede lo stato all'iPhone (all'apertura e quando torna raggiungibile).
    func requestState()
}

/// Sessione tenuta in memoria (dati di esempio o nessuna sessione).
@MainActor
@Observable
final class InMemoryWorkoutRemote: WorkoutRemote {
    private(set) var session: WorkoutSessionDTO?
    private(set) var restState: RemoteRest?
    var weightStep: Double = 2.5
    var accent: AccentPreset = .default
    /// Modificabile per le schermate di collaudo (fascia "iPhone non raggiungibile").
    var connection: RemoteConnection = .live

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

    func setRestEnd(endDate: Date, totalSeconds: Int) {}
    func skipRest() {}
    func requestState() {}
}
