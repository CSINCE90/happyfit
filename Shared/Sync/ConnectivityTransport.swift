import Foundation
import WatchConnectivity

/// Messaggio WatchConnectivity (dizionario di tipi property list) reso trasferibile tra thread.
struct Envelope: @unchecked Sendable {
    var value: [String: Any]
}

/// Chi riceve ciò che arriva dal trasporto (sempre sul main actor).
@MainActor
protocol ConnectivityTransportDelegate: AnyObject {
    /// Attivazione o raggiungibilità cambiate.
    func transportDidChange()
    func transport(didReceiveMessage message: Envelope, reply: @escaping (Envelope) -> Void)
    func transport(didReceiveContext context: Envelope)
    func transport(didReceiveUserInfo userInfo: Envelope)
}

/// Strato sottile sopra `WCSession`: si può sostituire con un falso nei test.
@MainActor
protocol ConnectivityTransport: AnyObject {
    var delegate: ConnectivityTransportDelegate? { get set }
    var isActivated: Bool { get }
    /// Il Watch (con la sua app in primo piano) o l'iPhone sono raggiungibili adesso.
    var isReachable: Bool { get }
    /// Si possono inviare dati in background: sull'iPhone serve un Watch abbinato con l'app installata.
    var canSendInBackground: Bool { get }
    /// Ultimo application context ricevuto (anche mentre l'app non girava).
    var receivedContext: Envelope? { get }

    func activate()
    func sendMessage(_ message: Envelope, reply: ((Envelope) -> Void)?, failure: ((Error) -> Void)?)
    func updateContext(_ context: Envelope)
    func transferUserInfo(_ userInfo: Envelope)
}

/// Realizzazione vera su `WCSession`.
@MainActor
final class WCSessionTransport: NSObject, ConnectivityTransport, WCSessionDelegate {
    weak var delegate: ConnectivityTransportDelegate?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    var isActivated: Bool { session?.activationState == .activated }
    var isReachable: Bool { isActivated && (session?.isReachable ?? false) }

    var canSendInBackground: Bool {
        guard let session, isActivated else { return false }
        #if os(iOS)
        return session.isPaired && session.isWatchAppInstalled
        #else
        return true
        #endif
    }

    var receivedContext: Envelope? {
        guard let context = session?.receivedApplicationContext, !context.isEmpty else { return nil }
        return Envelope(value: context)
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func sendMessage(_ message: Envelope, reply: ((Envelope) -> Void)?, failure: ((Error) -> Void)?) {
        guard isActivated, let session else {
            failure?(NSError(domain: "HappyFit.Sync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sessione non attiva"]))
            return
        }
        let replyBox = reply.map { handler in
            { (response: [String: Any]) in
                let envelope = Envelope(value: response)
                Task { @MainActor in handler(envelope) }
            }
        }
        let failureBox = failure.map { handler in
            { (error: Error) in
                let box = UncheckedBox(error)
                Task { @MainActor in handler(box.value) }
            }
        }
        session.sendMessage(message.value, replyHandler: replyBox, errorHandler: failureBox)
    }

    func updateContext(_ context: Envelope) {
        guard isActivated, let session else { return }
        try? session.updateApplicationContext(context.value)
    }

    func transferUserInfo(_ userInfo: Envelope) {
        guard isActivated, let session else { return }
        session.transferUserInfo(userInfo.value)
    }

    // MARK: WCSessionDelegate (chiamati su thread di sistema: si rientra sul main actor)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in delegate?.transportDidChange() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in delegate?.transportDidChange() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let envelope = Envelope(value: message)
        let box = UncheckedBox(replyHandler)
        Task { @MainActor in
            delegate?.transport(didReceiveMessage: envelope) { box.value($0.value) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let envelope = Envelope(value: message)
        Task { @MainActor in
            delegate?.transport(didReceiveMessage: envelope) { _ in }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let envelope = Envelope(value: applicationContext)
        Task { @MainActor in delegate?.transport(didReceiveContext: envelope) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let envelope = Envelope(value: userInfo)
        Task { @MainActor in delegate?.transport(didReceiveUserInfo: envelope) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Cambio di Watch abbinato: si riattiva la sessione per il nuovo.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in delegate?.transportDidChange() }
    }
    #endif
}

/// Scatola per valori non `Sendable` che WatchConnectivity ci consegna su thread di sistema.
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
