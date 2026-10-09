import AppKit
import UserNotifications
import YTTranscriptCore

/// Réception des clics sur les notifications système (ex. « Extraire » sur
/// le prompt d'URL YouTube copiée).
extension AppState: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier
        if let url = userInfo["url"] as? String,
           actionID == Notifier.extractAction
            || actionID == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                AppState.shared.add(urlsText: url, force: false)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        completionHandler()
    }

    /// Affiche aussi les notifications quand l'app est au premier plan.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
