import Foundation
import UserNotifications

/// Avviso di fine recupero quando il polso è abbassato (l'app è sospesa e non può vibrare da sola).
@MainActor
protocol RestNotificationScheduling: AnyObject {
    /// True se l'utente non ha ancora risposto alla richiesta di permesso.
    func needsAuthorization() async -> Bool
    /// Mostra la richiesta di sistema; true se concesso.
    func requestAuthorization() async -> Bool
    /// Programma (o riprogramma) l'avviso all'orario di fine.
    func schedule(at date: Date, exerciseName: String?)
    func cancel()
}

/// Notifica locale con UserNotifications: un solo avviso alla volta, sostituito a ogni riprogrammazione.
@MainActor
final class LocalRestNotifications: RestNotificationScheduling {
    static let identifier = "happyfit.rest-end"
    private let center = UNUserNotificationCenter.current()

    func needsAuthorization() async -> Bool {
        await center.notificationSettings().authorizationStatus == .notDetermined
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(at date: Date, exerciseName: String?) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0.5 else { return cancel() }
        let content = UNMutableNotificationContent()
        content.title = "Recupero finito"
        content.body = exerciseName.map { "Prossima serie: \($0)." } ?? "È ora della prossima serie."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        // Stesso identificatore: la richiesta precedente viene sostituita.
        center.add(request)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}

/// Con l'app in primo piano la notifica non viene mostrata: vibra già l'app (niente doppioni).
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
