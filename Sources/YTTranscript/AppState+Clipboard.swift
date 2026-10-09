import AppKit
import YTTranscriptCore

/// Surveillance du presse-papier : propose l'extraction quand une URL
/// YouTube y est copiée.
extension AppState {
    /// Active/désactive la vérification périodique (1 s) du presse-papier.
    func setClipboardWatch(enabled: Bool) {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        guard enabled else { return }
        lastPasteboardCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in AppState.shared.checkClipboard() }
        }
        // Laisse macOS regrouper les réveils (économie d'énergie).
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        clipboardTimer = timer
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastPasteboardCount else { return }
        lastPasteboardCount = pasteboard.changeCount

        guard let clip = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let videoID = youtubeVideoID(from: clip),
              !promptedVideoIDs.contains(videoID),
              !recents.contains(where: { $0.videoID == videoID && $0.exists }),
              !queue.contains(where: { youtubeVideoID(from: $0.url) == videoID })
        else { return }

        promptedVideoIDs.insert(videoID)
        Notifier.promptExtract(url: clip)
    }
}
