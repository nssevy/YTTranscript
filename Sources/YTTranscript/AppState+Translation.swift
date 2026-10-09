import Translation
import YTTranscriptCore

/// File de traduction : une traduction à la fois, hébergée par la tâche
/// .translationTask de ContentView (pilotée par `translationConfig`).
extension AppState {
    /// Démarre la traduction suivante si aucune n'est en cours.
    /// Piège SwiftUI : .translationTask ne repart que si la config CHANGE ;
    /// mêmes langues → invalidate(), sinon nouvelle config.
    func pumpTranslations() {
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

            guard let translated = try await translateInBatches(session: session, blocks: blocks, id: id)
            else {
                setDone(id, note: "Traduction annulée.")
                return
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

    /// Traduit les blocs par lots de 150 (moins d'allers-retours avec le
    /// moteur de traduction). `nil` si annulé en cours de route.
    private func translateInBatches(
        session: TranslationSession, blocks: [VTTParser.Segment], id: UUID
    ) async throws -> [String]? {
        var translated: [String] = []
        translated.reserveCapacity(blocks.count)
        let batchSize = 150
        var cursor = 0
        while cursor < blocks.count {
            if Task.isCancelled { return nil }
            let slice = Array(blocks[cursor..<min(cursor + batchSize, blocks.count)])
            let requests = slice.map { TranslationSession.Request(sourceText: $0.text) }
            let responses = try await session.translations(from: requests)
            translated.append(contentsOf: responses.map(\.targetText))
            cursor += slice.count
            setProgress(id, (translated.count, blocks.count))
        }
        return translated
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
}
