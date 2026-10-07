import Foundation
import SwiftData

/// Dati di esempio in memoria per le anteprime.
@MainActor
enum PreviewData {
    /// Container con catalogo, due schede e uno storico. Con `openSession` c'è anche un allenamento in corso.
    static func container(openSession: Bool = false) -> ModelContainer {
        // swiftlint:disable:next force_try
        let container = try! PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let service = WorkoutService(context: context)
        _ = try? ExerciseCatalog.seedIfNeeded(in: context)

        let exercises = (try? service.catalog()) ?? []
        func find(_ name: String) -> Exercise { exercises.first { $0.name == name } ?? exercises[0] }

        let push = try? service.createTemplate(name: "Push", exercises: [
            (find("Panca piana con bilanciere"), 4, 8, 120),
            (find("Military press"), 3, 10, 90),
            (find("Push down ai cavi"), 3, 12, 60)
        ])
        _ = try? service.createTemplate(name: "Gambe", exercises: [
            (find("Squat con bilanciere"), 4, 6, 180),
            (find("Leg press"), 3, 12, 120)
        ])

        // Storico: due allenamenti completati.
        if let push {
            for (offset, base) in [(-7, 50.0), (-3, 52.5)] {
                let start = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
                if let session = try? service.startSession(from: push, at: start) {
                    for item in session.sortedExercises {
                        for entry in item.sortedSets {
                            try? service.completeSet(entry, weightKg: base, reps: 8, at: start.addingTimeInterval(600))
                        }
                    }
                    try? service.finish(session, at: start.addingTimeInterval(3_600))
                }
            }
            if openSession {
                if let session = try? service.startSession(from: push) {
                    if let first = session.sortedExercises.first?.sortedSets.first {
                        try? service.completeSet(first, weightKg: 55, reps: 8)
                    }
                }
            }
        }
        return container
    }

    static func template(in container: ModelContainer) -> WorkoutTemplate {
        let all = (try? container.mainContext.fetch(FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.order)]))) ?? []
        return all[0]
    }

    static func openSession(in container: ModelContainer) -> WorkoutSession {
        let service = WorkoutService(context: container.mainContext)
        // swiftlint:disable:next force_try
        return try! service.openSession()!
    }

    static func closedSession(in container: ModelContainer) -> WorkoutSession {
        let all = (try? container.mainContext.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil }))) ?? []
        return all[0]
    }

    static func exercise(in container: ModelContainer) -> Exercise {
        let all = (try? container.mainContext.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return all[0]
    }
}
