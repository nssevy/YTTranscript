import SwiftUI
import AppKit
import Translation
import UserNotifications

/// Un élément de la file d'extraction.
struct QueueItem: Identifiable {
    enum Status {
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
@MainActor
final class AppState: NSObject, ObservableObject {
    static let shared = AppState()

    @Published var queue: [QueueItem] = []
    @Published var recents: [RecentEntry] = RecentStore.load()
    @Published var missingIDs: Set<String> = []
    /// Non-nil → la vue hôte (.translationTask sur ContentView) traduit.
    @Published var translationConfig: TranslationSession.Configuration?
    @Published var ytDlpUpdateAvailable = false

    private var isExtracting = false
    /// IDs des items en attente de traduction, dans l'ordre.
    private var pendingTranslations: [UUID] = []
    private var currentTranslationID: UUID?
    private var clipboardTimer: Timer?
    private var lastPasteboardCount = NSPasteboard.general.changeCount
    /// Derniers IDs vidéo proposés en notification (anti-spam).
    private var promptedVideoIDs: Set<String> = []

    private var outputDir: URL {
        let path = UserDefaults.standard.string(forKey: "outputDir")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Transcripts").path
        return URL(fileURLWithPath: path)
    }

    private var targetLang: String {
        UserDefaults.standard.string(forKey: "targetLang") ?? "fr"
    }

    private var autoTranslate: Bool {
        UserDefaults.standard.object(forKey: "autoTranslate") as? Bool ?? true
    }

    private var notifyOnDone: Bool {
        UserDefaults.standard.object(forKey: "notifyOnDone") as? Bool ?? true
    }

    private var srtLineWidth: Int {
        let value = UserDefaults.standard.integer(forKey: "srtLineWidth")
        return value > 0 ? value : VTTParser.defaultSRTLineWidth
    }

    // MARK: - File d'extraction

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

    // MARK: - File de traduction

    /// Démarre la traduction suivante si aucune n'est en cours.
    /// Piège SwiftUI : .translationTask ne repart que si la config CHANGE ;
    /// mêmes langues → invalidate(), sinon nouvelle config.
    private func pumpTranslations() {
        guard currentTranslationID == nil, let next = pendingTranslations.first else { return }
        currentTranslationID = next
        let targetLanguage = Locale.Language(identifier: targetLang)
        if translationConfig != nil, translationConfig?.target == targetLanguage {
            translationConfig?.invalidate()
        } else {
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: targetLanguage
            )
        }
    }

    /// Corps de la tâche .translationTask (hébergée par ContentView).
    func runTranslation(session: TranslationSession) async {
        guard let id = currentTranslationID,
              let index = queue.firstIndex(where: { $0.id == id }),
              let extraction = queue[index].result
        else {
            currentTranslationID = nil
            return
        }

        defer {
            pendingTranslations.removeAll { $0 == id }
            currentTranslationID = nil
            pumpTranslations()
        }

        do {
            try await session.prepareTranslation()

            // Blocs courts et lisibles (les auto-subs YouTube produisent des
            // cues « flash » de 10 ms qui clignoteraient à l'écran).
            let blocks = VTTParser.groupForSRT(extraction.segments, lineWidth: srtLineWidth)
            setProgress(id, (0, blocks.count))

            var translated: [String] = []
            translated.reserveCapacity(blocks.count)
            // Gros lots = moins d'allers-retours avec le moteur de traduction.
            let batchSize = 150
            var cursor = 0
            while cursor < blocks.count {
                if Task.isCancelled {
                    setDone(id, note: "Traduction annulée.")
                    return
                }
                let slice = Array(blocks[cursor..<min(cursor + batchSize, blocks.count)])
                let requests = slice.map { TranslationSession.Request(sourceText: $0.text) }
                let responses = try await session.translations(from: requests)
                translated.append(contentsOf: responses.map(\.targetText))
                cursor += slice.count
                setProgress(id, (translated.count, blocks.count))
            }

            let srt = VTTParser.renderSRT(segments: blocks, translatedTexts: translated,
                                          lineWidth: srtLineWidth)
            let srtURL = extraction.fileURL.deletingPathExtension()
                .appendingPathExtension("\(targetLang).srt")
            try srt.write(to: srtURL, atomically: true, encoding: .utf8)

            if let idx = queue.firstIndex(where: { $0.id == id }) {
                queue[idx].result?.srtURL = srtURL
                if let updated = queue[idx].result {
                    recordRecent(updated, videoID: youtubeVideoID(from: queue[idx].url))
                }
            }
            setDone(id, note: nil)
            notify(title: "Traduction terminée", body: srtURL.lastPathComponent)
        } catch is CancellationError {
            setDone(id, note: "Traduction annulée.")
        } catch {
            setDone(id, note: "Traduction indisponible (\(error.localizedDescription))")
        }
    }

    /// Annule la traduction en cours (le .txt est déjà écrit).
    func cancelTranslation(_ id: UUID) {
        if currentTranslationID == id {
            translationConfig = nil // détruit la tâche .translationTask
            currentTranslationID = nil
        }
        pendingTranslations.removeAll { $0 == id }
        setDone(id, note: "Traduction annulée.")
        pumpTranslations()
    }

    private func setProgress(_ id: UUID, _ progress: (Int, Int)) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].progress = progress
    }

    private func setDone(_ id: UUID, note: String?) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].status = .done
        queue[index].note = note
        queue[index].progress = nil
        queue[index].result?.segments = [] // plus besoin, libère la mémoire
    }

    // MARK: - Historique

    /// `reload` : redécode le JSON de l'historique (après une modification
    /// externe). Sinon, simple re-vérification d'existence des fichiers
    /// (quelques stat(), pas de décodage toutes les 5 s).
    func refreshRecents(reload: Bool = false) {
        if reload || recents.isEmpty {
            recents = RecentStore.load()
        }
        missingIDs = Set(recents.filter { !$0.exists }.map(\.id))
    }

    private func recordRecent(_ extraction: ExtractionResult, videoID: String?) {
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

    // MARK: - Surveillance du presse-papier

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

    // MARK: - Vérification yt-dlp

    /// Au lancement : signale si Homebrew connaît une version plus récente.
    func checkYtDlpUpdate() {
        Task.detached(priority: .utility) {
            let brewPath = "/opt/homebrew/bin/brew"
            guard FileManager.default.isExecutableFile(atPath: brewPath) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["outdated", "--quiet", "yt-dlp"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()
            let outdated = String(data: data, encoding: .utf8)?
                .contains("yt-dlp") ?? false
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

    // MARK: - Divers

    private func notify(title: String, body: String) {
        guard notifyOnDone else { return }
        Notifier.send(title: title, body: body)
    }
}

// MARK: - Réception des clics de notification

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
