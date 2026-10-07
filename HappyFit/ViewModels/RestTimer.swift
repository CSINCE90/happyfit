import Foundation

/// Timer di recupero basato su una data di scadenza: resta corretto anche se l'app va in background.
struct RestTimer: Equatable {
    private(set) var endDate: Date
    private(set) var totalSeconds: Int

    init(seconds: Int, now: Date = Date()) {
        totalSeconds = max(seconds, 0)
        endDate = now.addingTimeInterval(TimeInterval(totalSeconds))
    }

    func remaining(at now: Date) -> TimeInterval {
        max(endDate.timeIntervalSince(now), 0)
    }

    /// Secondi interi rimanenti (arrotondati per eccesso, per non mostrare 0 prima della fine).
    func remainingSeconds(at now: Date) -> Int {
        Int(remaining(at: now).rounded(.up))
    }

    func isFinished(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }

    mutating func add(seconds: Int) {
        endDate = endDate.addingTimeInterval(TimeInterval(seconds))
        totalSeconds = max(totalSeconds + seconds, 0)
    }
}
