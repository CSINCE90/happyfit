import Foundation

/// Formattazione di pesi, durate e date per l'interfaccia.
enum Formatting {
    /// "52,5" o "50" (senza zeri inutili).
    static func weight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "50 × 8"
    static func setSummary(weightKg: Double, reps: Int) -> String {
        "\(weight(weightKg)) × \(reps)"
    }

    /// "1:30"
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(seconds, 0) / 60, max(seconds, 0) % 60)
    }

    /// "90 s" oppure "2 min" / "1 min 30 s"
    static func rest(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60, rest = seconds % 60
        return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
    }

    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(Int(end.timeIntervalSince(start) / 60), 0)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    /// Converte il testo di un campo ("52,5" o "52.5") in numero.
    static func parseNumber(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

extension MuscleGroup {
    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
