import Foundation
import YTTranscriptCore

/// Vérification de mise à jour yt-dlp au lancement.
extension AppState {
    /// Au lancement : signale si Homebrew connaît une version plus récente.
    func checkYtDlpUpdate() {
        Task.detached(priority: .utility) {
            let outdated = Extractor.isUpdateAvailable()
            await MainActor.run {
                AppState.shared.ytDlpUpdateAvailable = outdated
                if outdated {
                    AppState.shared.notify(
                        title: "Mise à jour disponible",
                        body: "Une nouvelle version de yt-dlp est disponible (Paramètres → Maintenance)."
                    )
                }
            }
        }
    }
}
