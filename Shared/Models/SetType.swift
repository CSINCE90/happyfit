import Foundation

/// Tipo di serie.
enum SetType: String, Codable, Sendable, CaseIterable {
    case warmup
    case normal
    case failure
}
