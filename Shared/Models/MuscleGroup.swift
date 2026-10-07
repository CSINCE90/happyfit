import Foundation

/// Gruppo muscolare di un esercizio del catalogo.
enum MuscleGroup: String, Codable, Sendable, CaseIterable {
    case petto
    case schiena
    case gambe
    case spalle
    case braccia
    case core
}
