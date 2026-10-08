#if DEBUG
import Foundation
import SwiftUI
import OSLog

/// Solo collaudo: `-debugScreen <nome>` apre una schermata con dati di esempio. Non esiste in Release.
/// Senza argomento l'app mostra la sessione di esempio.
@MainActor
enum WatchDebugLaunch {
    static var screen: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-debugScreen"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    /// `-debugTextSize ax`: testo di accessibilità grande (il simulatore watchOS non permette di cambiarlo da fuori).
    static var textSize: DynamicTypeSize? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-debugTextSize"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1] == "ax" ? .accessibility3 : .large
    }

    /// `-debugCompleteAfter N`: dopo N secondi completa la serie mostrata come farebbe un tocco sul Watch.
    static func scheduleAutoCompleteIfRequested(viewModel: WatchSessionViewModel) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-debugCompleteAfter"), args.indices.contains(index + 1),
              let seconds = Double(args[index + 1]) else { return }
        let log = Logger(subsystem: "com.csince90.happyfit", category: "sync")
        log.notice("WATCH-DEBUG completamento automatico programmato tra \(seconds, privacy: .public) s")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            log.notice("WATCH-DEBUG completa serie alle \(Date().timeIntervalSince1970, privacy: .public) schermata=\(String(describing: viewModel.screen), privacy: .public)")
            viewModel.completeShownSet()
        }
    }

    static func makeViewModel() -> WatchSessionViewModel {
        let name = screen
        // Nelle schermate di collaudo niente richiesta di permesso reale (tranne "permission").
        let notifications: any RestNotificationScheduling = name == nil ? LocalRestNotifications() : SilentRestNotifications()
        let session: WorkoutSessionDTO? = switch name {
        case "none": nil
        case "done": WatchSampleData.completedSession
        default: WatchSampleData.session
        }
        let remote = InMemoryWorkoutRemote(session: session)
        if name == "offline" { remote.connection = .offline(lastUpdate: Date().addingTimeInterval(-300)) }
        let viewModel = WatchSessionViewModel(remote: remote, notifications: notifications)
        switch name {
        case "crown": viewModel.select(.weight)
        case "rest": viewModel.startRest(seconds: 90)
        case "permission": viewModel.showPermissionExplanation = true
        default: break
        }
        return viewModel
    }
}

/// Avvisi che non fanno nulla (scatti di collaudo e anteprime).
@MainActor
final class SilentRestNotifications: RestNotificationScheduling {
    func needsAuthorization() async -> Bool { false }
    func requestAuthorization() async -> Bool { false }
    func schedule(at date: Date, exerciseName: String?) {}
    func cancel() {}
}

/// Sessione di esempio: Push con tre esercizi, la prima serie della panca già fatta.
enum WatchSampleData {
    private static let start = Date().addingTimeInterval(-900)
    private static let pancaID = UUID()
    private static let militaryID = UUID()

    private static func sets(_ count: Int, weight: Double, reps: Int, done: Int = 0) -> [SetEntryDTO] {
        (0..<count).map { index in
            SetEntryDTO(id: UUID(), order: index, weightKg: weight, reps: reps, type: .normal,
                        completedAt: index < done ? start.addingTimeInterval(Double(index) * 120) : nil)
        }
    }

    static let session = WorkoutSessionDTO(
        id: UUID(), name: "Push", startedAt: start, endedAt: nil,
        exercises: [
            SessionExerciseDTO(id: UUID(), exercise: ExerciseDTO(id: pancaID, name: "Panca piana con bilanciere"), order: 0, restSeconds: 120, sets: sets(4, weight: 52.5, reps: 8, done: 1)),
            SessionExerciseDTO(id: UUID(), exercise: ExerciseDTO(id: militaryID, name: "Military press"), order: 1, restSeconds: 90, sets: sets(3, weight: 30, reps: 10)),
            SessionExerciseDTO(id: UUID(), exercise: ExerciseDTO(id: UUID(), name: "Push down ai cavi"), order: 2, restSeconds: 60, sets: sets(3, weight: 25, reps: 12))
        ],
        previousSets: [
            pancaID: sets(4, weight: 50, reps: 8, done: 4),
            militaryID: sets(3, weight: 27.5, reps: 10, done: 3)
        ]
    )

    static var completedSession: WorkoutSessionDTO {
        var copy = session
        for e in copy.exercises.indices {
            for s in copy.exercises[e].sets.indices where copy.exercises[e].sets[s].completedAt == nil {
                copy.exercises[e].sets[s].completedAt = start
            }
        }
        return copy
    }
}
#endif
