import Foundation
import YTTranscriptCore

/// Historique des extractions (persisté par RecentStore, côté Core).
extension AppState {
    /// `reload` : redécode le JSON de l'historique (après une modification
    /// externe). Sinon, simple re-vérification d'existence des fichiers
    /// (quelques stat(), pas de décodage toutes les 5 s).
    func refreshRecents(reload: Bool = false) {
        if reload || recents.isEmpty {
            recents = RecentStore.load()
        }
        missingIDs = Set(recents.filter { !$0.exists }.map(\.id))
    }

    func recordRecent(_ extraction: ExtractionResult, videoID: String?) {
        let entry = RecentEntry(
            title: extraction.title,
            txtPath: extraction.fileURL.path,
            srtPath: extraction.srtURL?.path,
            date: Date(),
            videoID: videoID,
            channel: extraction.channel,
            duration: extraction.duration,
            thumbnailURL: extraction.thumbnailURL
        )
        recents = RecentStore.add(entry)
    }
}
