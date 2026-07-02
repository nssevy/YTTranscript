import Foundation
import UserNotifications

/// Notifications macOS de fin de tâche (.txt prêt, .srt traduit).
enum Notifier {
    /// À appeler avant le premier envoi (dialogue système une seule fois).
    static func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // immédiate
        )
        UNUserNotificationCenter.current().add(request)
    }
}
