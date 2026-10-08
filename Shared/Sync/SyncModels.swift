import Foundation

// Messaggi effimeri tra iPhone e Watch. Nulla di quanto segue viene salvato in SwiftData né cambia i DTO persistenti:
// i DTO della sessione viaggiano così come sono dentro `SyncState`.

/// Impostazioni condivise dall'iPhone al Watch.
struct SyncSettings: Codable, Equatable, Sendable {
    var weightStep: Double
    var accentRaw: String
}

/// Stato della sessione, dall'iPhone (unica fonte dei dati) al Watch.
struct SyncState: Codable, Equatable, Sendable {
    /// Crescente anche dopo riavvii (vedi `RevisionClock`): il Watch scarta gli stati con revisione più bassa.
    var revision: Int64
    /// Quando l'iPhone ha costruito lo stato.
    var sentAt: Date
    /// Sessione aperta (nil = nessun allenamento in corso).
    var session: WorkoutSessionDTO?
    /// Orario di fine del recupero (assoluto), solo se ancora nel futuro.
    var restEnd: Date?
    var restTotalSeconds: Int?
    var settings: SyncSettings

    /// Vero se il contenuto è identico a quello di `other`, esclusi revisione e orario d'invio.
    func hasSameContent(as other: SyncState) -> Bool {
        var a = self, b = other
        a.revision = 0; b.revision = 0
        a.sentAt = .distantPast; b.sentAt = .distantPast
        return a == b
    }

    /// Copia senza lo storico "ultima volta": più leggera, per quando lo stato completo supera il tetto prudente.
    func trimmed() -> SyncState {
        var copy = self
        copy.session?.previousSets = [:]
        return copy
    }
}

/// Comando dal Watch all'iPhone. Si riferisce sempre a una serie precisa (mai "la prossima incompleta"),
/// quindi un comando ripetuto o in ritardo non può completare una serie diversa.
struct WatchCommand: Codable, Equatable, Sendable, Identifiable {
    enum Action: Codable, Equatable, Sendable {
        case completeSet(setID: UUID, exerciseID: UUID)
        /// Valori assoluti (idempotenti), mai incrementi.
        case setValues(setID: UUID, exerciseID: UUID, weightKg: Double?, reps: Int?)
        /// Fine del recupero come orario assoluto (idempotente, sostituisce "±15").
        case setRestEnd(endDate: Date, totalSeconds: Int)
        case skipRest
    }

    let id: UUID
    let sessionID: UUID
    /// Orario d'invio: è anche il `completedAt` della serie completata dal Watch.
    let sentAt: Date
    let action: Action

    init(id: UUID = UUID(), sessionID: UUID, sentAt: Date = Date(), action: Action) {
        self.id = id
        self.sessionID = sessionID
        self.sentAt = sentAt
        self.action = action
    }

    /// I comandi sul recupero hanno senso solo "adesso": non si accodano se l'iPhone non è raggiungibile.
    var isTimeSensitive: Bool {
        switch action {
        case .setRestEnd, .skipRest: return true
        case .completeSet, .setValues: return false
        }
    }
}

/// Tetti prudenti: Apple non documenta un limite numerico per i dati di `WCSession`.
enum SyncLimits {
    /// Oltre questa dimensione (JSON) lo stato viene inviato senza storico.
    static let softPayloadBytes = 48_000
    /// Dopo quanto un ultimo stato salvato sul Watch non è più affidabile.
    static let savedStateLifetime: TimeInterval = 12 * 3600
    /// Intervallo minimo tra due invii di stato dall'iPhone (dopo l'intervallo parte sempre un invio finale).
    static let minPublishInterval: TimeInterval = 0.5
    /// Intervallo minimo tra due invii causati da cambi di raggiungibilità/attivazione.
    static let transportPublishCooldown: TimeInterval = 2
    /// Quanti id di comandi già applicati l'iPhone ricorda.
    static let rememberedCommands = 200
}

/// Orologio delle revisioni: `max(ultima + 1, millisecondi dall'epoca)`, con l'ultima persistita.
/// Sopravvive a riavvii e avvii in background; non riparte mai da zero.
final class RevisionClock {
    private let defaults: UserDefaults
    private let key: String
    private let now: () -> Date
    private var last: Int64

    init(defaults: UserDefaults = .standard, key: String = "syncRevision", now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.key = key
        self.now = now
        self.last = (defaults.object(forKey: key) as? NSNumber)?.int64Value ?? 0
    }

    func next() -> Int64 {
        let candidate = max(last + 1, Int64(now().timeIntervalSince1970 * 1000))
        last = candidate
        defaults.set(NSNumber(value: candidate), forKey: key)
        return candidate
    }
}

/// Codifica dei messaggi come dizionari di tipi property list (richiesto da WatchConnectivity):
/// `kind` più un blob JSON in `payload`.
enum SyncCodec {
    enum Kind: String {
        case command, state, requestState, ack
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func envelope<T: Encodable>(_ kind: Kind, _ value: T) -> Envelope? {
        guard let data = try? encoder.encode(value) else { return nil }
        return Envelope(value: ["kind": kind.rawValue, "payload": data])
    }

    static func requestStateEnvelope() -> Envelope {
        Envelope(value: ["kind": Kind.requestState.rawValue])
    }

    static func ackEnvelope(for id: UUID) -> Envelope {
        Envelope(value: ["kind": Kind.ack.rawValue, "id": id.uuidString])
    }

    static func kind(of envelope: Envelope) -> Kind? {
        (envelope.value["kind"] as? String).flatMap(Kind.init(rawValue:))
    }

    static func decodeCommand(_ envelope: Envelope) -> WatchCommand? {
        decode(WatchCommand.self, from: envelope, expecting: .command)
    }

    static func decodeState(_ envelope: Envelope) -> SyncState? {
        decode(SyncState.self, from: envelope, expecting: .state)
    }

    static func ackID(_ envelope: Envelope) -> UUID? {
        guard kind(of: envelope) == .ack, let text = envelope.value["id"] as? String else { return nil }
        return UUID(uuidString: text)
    }

    /// Stato come dati JSON (per salvare l'ultimo stato noto sul Watch).
    static func data(_ state: SyncState) -> Data? {
        try? encoder.encode(state)
    }

    static func state(from data: Data) -> SyncState? {
        try? decoder.decode(SyncState.self, from: data)
    }

    /// Dimensione in byte del JSON di un valore (per rispettare il tetto prudente).
    static func encodedSize<T: Encodable>(_ value: T) -> Int {
        (try? encoder.encode(value).count) ?? 0
    }

    /// Stato pronto da inviare: completo, oppure senza storico se supera il tetto prudente.
    static func stateEnvelope(_ state: SyncState) -> Envelope? {
        let candidate = encodedSize(state) <= SyncLimits.softPayloadBytes ? state : state.trimmed()
        return envelope(.state, candidate)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from envelope: Envelope, expecting kind: Kind) -> T? {
        guard Self.kind(of: envelope) == kind, let data = envelope.value["payload"] as? Data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
