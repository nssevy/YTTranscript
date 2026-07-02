import Foundation
import UserNotifications

/// Notifications macOS : fins de tâche + proposition d'extraction quand une
/// URL YouTube est copiée (surveillance du presse-papier).
enum Notifier {
    static let extractCategory = "YT_URL"
    static let extractAction = "EXTRACT"

    /// À appeler au lancement : enregistre la catégorie « Extraire » et le
    /// délégué qui reçoit les clics sur les notifications.
    static func configure(delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()
        let action = UNNotificationAction(identifier: extractAction,
                                          title: "Extraire", options: [])
        let category = UNNotificationCategory(identifier: extractCategory,
                                              actions: [action],
                                              intentIdentifiers: [])
        center.setNotificationCategories([category])
        center.delegate = delegate
    }

    /// Dialogue système une seule fois.
    static func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        deliver(content)
    }

    /// « URL YouTube copiée — Extraire ? » avec bouton d'action.
    static func promptExtract(url: String) {
        let content = UNMutableNotificationContent()
        content.title = "URL YouTube détectée"
        content.body = url
        content.categoryIdentifier = extractCategory
        content.userInfo = ["url": url]
        deliver(content)
    }

    private static func deliver(_ content: UNNotificationContent) {
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // immédiate
        )
        UNUserNotificationCenter.current().add(request)
    }
}
