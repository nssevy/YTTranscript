import SwiftUI
import AppKit
import Translation
import UserNotifications
import YTTranscriptCore

/// Un élément de la file d'extraction.
struct QueueItem: Identifiable {
    enum Status: Equatable {
        case pending        // en attente d'extraction
        case expanding      // playlist en cours d'énumération
        case duplicate      // déjà extrait, en attente de décision
        case extracting
        case translating
        case done
        case failed
    }

    let id = UUID()
    let url: String
    var status: Status = .pending
    var title: String?
    var result: ExtractionResult?
    var errorText: String?
    var note: String?
    /// Progression de traduction (blocs faits, total).
    var progress: (done: Int, total: Int)?
    /// Sous-dossier de sortie (ex. "Playlist - Deep learning") pour grouper
    /// les vidéos d'une même playlist.
    var outputSubdir: String?

    var displayTitle: String { title ?? url }
}

/// État partagé de l'app : file d'extraction séquentielle, file de traduction,
/// surveillance du presse-papier, historique, vérification yt-dlp.
/// Partagé entre la fenêtre principale, la barre de menus et les notifications.
///
/// La logique est répartie par responsabilité dans des extensions séparées
/// (AppState+Queue, AppState+Translation, AppState+History,
/// AppState+Clipboard, AppState+YtDlpUpdate, AppState+Notifications) ; ce
/// fichier ne porte que l'état partagé et les accesseurs communs.
@MainActor
final class AppState: NSObject, ObservableObject {
    static let shared = AppState()

    @Published var queue: [QueueItem] = []
    @Published var recents: [RecentEntry] = RecentStore.load()
    @Published var missingIDs: Set<String> = []
    /// Non-nil → la vue hôte (.translationTask sur ContentView) traduit.
    @Published var translationConfig: TranslationSession.Configuration?
    @Published var ytDlpUpdateAvailable = false

    var isExtracting = false
    /// IDs des items en attente de traduction, dans l'ordre.
    var pendingTranslations: [UUID] = []
    var currentTranslationID: UUID?
    var clipboardTimer: Timer?
    var lastPasteboardCount = NSPasteboard.general.changeCount
    /// Derniers IDs vidéo proposés en notification (anti-spam).
    var promptedVideoIDs: Set<String> = []

    var outputDir: URL {
        let path = UserDefaults.standard.string(forKey: "outputDir")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Transcripts").path
        return URL(fileURLWithPath: path)
    }

    var targetLang: String {
        UserDefaults.standard.string(forKey: "targetLang") ?? "fr"
    }

    var autoTranslate: Bool {
        UserDefaults.standard.object(forKey: "autoTranslate") as? Bool ?? true
    }

    var notifyOnDone: Bool {
        UserDefaults.standard.object(forKey: "notifyOnDone") as? Bool ?? true
    }

    var srtLineWidth: Int {
        let value = UserDefaults.standard.integer(forKey: "srtLineWidth")
        return value > 0 ? value : VTTParser.defaultSRTLineWidth
    }

    func notify(title: String, body: String) {
        guard notifyOnDone else { return }
        Notifier.send(title: title, body: body)
    }
}
