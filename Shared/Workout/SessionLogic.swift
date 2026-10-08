import Foundation

/// Posizione di una serie in una sessione (indici negli elenchi ordinati per `order`).
struct SetPosition: Equatable, Sendable {
    let exerciseIndex: Int
    let setIndex: Int
}

/// Regole pure sui DTO della sessione: nessuno stato, nessuna dipendenza (usate dal Watch, testabili).
enum SessionLogic {
    /// Peso massimo impostabile (kg) e ripetizioni massime: limiti di sicurezza della Digital Crown.
    static let maxWeightKg: Double = 500
    static let maxReps = 100

    static func orderedExercises(_ session: WorkoutSessionDTO) -> [SessionExerciseDTO] {
        session.exercises.sorted { $0.order < $1.order }
    }

    static func orderedSets(_ exercise: SessionExerciseDTO) -> [SetEntryDTO] {
        exercise.sets.sorted { $0.order < $1.order }
    }

    /// Prima serie incompleta di un esercizio, se c'è.
    static func firstIncompleteSetIndex(_ exercise: SessionExerciseDTO) -> Int? {
        orderedSets(exercise).firstIndex { $0.completedAt == nil }
    }

    /// Esercizio e serie correnti: il primo esercizio con una serie incompleta, e la sua prima serie incompleta.
    /// Nil se tutte le serie sono completate (o la sessione non ha serie).
    static func current(in session: WorkoutSessionDTO) -> SetPosition? {
        for (index, exercise) in orderedExercises(session).enumerated() {
            if let setIndex = firstIncompleteSetIndex(exercise) {
                return SetPosition(exerciseIndex: index, setIndex: setIndex)
            }
        }
        return nil
    }

    /// Serie mostrata: la prima incompleta dell'esercizio scelto, se ne ha ancora; altrimenti quella corrente.
    static func displayed(in session: WorkoutSessionDTO, preferredExerciseID: UUID?) -> SetPosition? {
        let exercises = orderedExercises(session)
        if let preferredExerciseID,
           let index = exercises.firstIndex(where: { $0.id == preferredExerciseID }),
           let setIndex = firstIncompleteSetIndex(exercises[index]) {
            return SetPosition(exerciseIndex: index, setIndex: setIndex)
        }
        return current(in: session)
    }

    /// Serie completate e totali di un esercizio.
    static func progress(_ exercise: SessionExerciseDTO) -> (completed: Int, total: Int) {
        (exercise.sets.filter { $0.completedAt != nil }.count, exercise.sets.count)
    }

    /// Valore "ultima volta" per la serie numero `setIndex` (0 = prima): la serie con lo stesso numero
    /// della sessione precedente; se quella volta ne erano state fatte meno, l'ultima completata.
    /// Nil se non c'è storico per l'esercizio.
    static func previousSet(in session: WorkoutSessionDTO, exercise: SessionExerciseDTO, setIndex: Int) -> SetEntryDTO? {
        guard let previous = session.previousSets[exercise.exercise.id], !previous.isEmpty else { return nil }
        let ordered = previous.sorted { $0.order < $1.order }
        return setIndex < ordered.count ? ordered[setIndex] : ordered.last
    }

    /// Copia della sessione con la serie indicata completata.
    static func completingSet(_ setID: UUID, of exerciseID: UUID, in session: WorkoutSessionDTO, at date: Date) -> WorkoutSessionDTO {
        updatingSet(setID, of: exerciseID, in: session) { $0.completedAt = date }
    }

    /// Copia della sessione con peso e/o ripetizioni della serie cambiati (limitati a 0...massimo).
    static func settingValues(of setID: UUID, of exerciseID: UUID, in session: WorkoutSessionDTO, weightKg: Double?, reps: Int?) -> WorkoutSessionDTO {
        updatingSet(setID, of: exerciseID, in: session) { set in
            if let weightKg { set.weightKg = min(max(weightKg, 0), maxWeightKg) }
            if let reps { set.reps = min(max(reps, 0), maxReps) }
        }
    }

    private static func updatingSet(_ setID: UUID, of exerciseID: UUID, in session: WorkoutSessionDTO, _ change: (inout SetEntryDTO) -> Void) -> WorkoutSessionDTO {
        var copy = session
        guard let e = copy.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = copy.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return session }
        change(&copy.exercises[e].sets[s])
        return copy
    }
}
