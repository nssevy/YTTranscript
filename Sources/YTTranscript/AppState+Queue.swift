import Foundation
import YTTranscriptCore

/// File d'extraction séquentielle : ajout d'URLs, dépliage de playlists,
/// doublons, exécution d'un item à la fois.
extension AppState {
    /// Ajoute une ou plusieurs URLs (séparées par espaces/retours à la ligne).
    /// Tout ce qui ne ressemble pas à une URL YouTube (vidéo ou playlist) est
    /// IGNORÉ : coller une phrase ne remplit plus la file de déchets.
    /// Les playlists sont dépliées en vidéos individuelles.
    func add(urlsText: String, force: Bool = false) {
        let urls = urlsText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { youtubeVideoID(from: $0) != nil || Extractor.isPlaylist($0) }
        for url in urls { enqueue(url, force: force, subdir: nil) }
        processNextIfIdle()
    }

    private func enqueue(_ url: String, force: Bool, subdir: String?) {
        if Extractor.isPlaylist(url) {
            var item = QueueItem(url: url)
            item.status = .expanding
            item.title = "Playlist…"
            queue.append(item)
            let itemID = item.id
            Task.detached(priority: .userInitiated) {
                let info = try? Extractor.playlistInfo(url)
                await MainActor.run { self.expandPlaylist(itemID, with: info) }
            }
            return
        }

        // Doublon : déjà extrait et fichiers toujours sur disque.
        if !force, let videoID = youtubeVideoID(from: url),
           let existing = recents.first(where: { $0.videoID == videoID && $0.exists }) {
            var item = QueueItem(url: url)
            item.status = .duplicate
            item.title = existing.title
            item.outputSubdir = subdir // conservé si « Extraire quand même »
            queue.append(item)
            return
        }
        var item = QueueItem(url: url)
        item.outputSubdir = subdir
        queue.append(item)
    }

    private func expandPlaylist(_ id: UUID, with info: Extractor.PlaylistInfo?) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        if let info {
            queue.remove(at: index)
            // Toutes les vidéos de la playlist dans un dossier commun.
            let subdir = "Playlist - " + Extractor.sanitizeFilename(info.title)
            for url in info.videoURLs { enqueue(url, force: false, subdir: subdir) }
        } else {
            queue[index].status = .failed
            queue[index].errorText = "Playlist introuvable ou vide."
        }
        processNextIfIdle()
    }

    /// Relance un doublon ou un échec.
    func forceExtract(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].status = .pending
        queue[index].errorText = nil
        processNextIfIdle()
    }

    func removeItem(_ id: UUID) {
        queue.removeAll { $0.id == id && $0.status != .extracting && $0.status != .translating }
    }

    /// Retire les éléments terminés/échoués/doublons de la file.
    func clearFinished() {
        queue.removeAll { $0.status == .done || $0.status == .failed || $0.status == .duplicate }
    }

    var hasActiveWork: Bool {
        queue.contains { [.pending, .expanding, .extracting, .translating].contains($0.status) }
    }

    private func processNextIfIdle() {
        guard !isExtracting,
              let index = queue.firstIndex(where: { $0.status == .pending })
        else { return }
        isExtracting = true
        queue[index].status = .extracting
        let item = queue[index]
        // Vidéo de playlist → sous-dossier commun "Playlist - <titre>".
        let destination = item.outputSubdir.map { outputDir.appendingPathComponent($0) }
            ?? outputDir

        Task.detached(priority: .userInitiated) {
            let outcome: Result<ExtractionResult, Error> = Result {
                try Extractor.extract(videoURL: item.url, outputDir: destination)
            }
            await MainActor.run { self.finishExtraction(item.id, outcome) }
        }
    }

    private func finishExtraction(_ id: UUID, _ outcome: Result<ExtractionResult, Error>) {
        isExtracting = false
        defer { processNextIfIdle() }
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }

        switch outcome {
        case .success(let extraction):
            queue[index].result = extraction
            queue[index].title = extraction.title
            recordRecent(extraction, videoID: youtubeVideoID(from: queue[index].url))
            notify(title: "Transcript prêt", body: extraction.fileURL.lastPathComponent)
            if autoTranslate, extraction.sourceIsEnglish, targetLang != "en",
               !extraction.segments.isEmpty {
                queue[index].status = .translating
                pendingTranslations.append(id)
                pumpTranslations()
            } else {
                queue[index].status = .done
                queue[index].result?.segments = [] // plus besoin, libère la mémoire
            }
        case .failure(ExtractionError.ytDlpMissing):
            queue[index].status = .failed
            queue[index].errorText = "yt-dlp est introuvable. Installez-le avec : brew install yt-dlp ffmpeg"
        case .failure:
            queue[index].status = .failed
            queue[index].errorText = "Cette vidéo est invalide ou ne correspond pas aux critères requis."
        }
    }
}
