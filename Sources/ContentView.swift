import SwiftUI
import AppKit
import Translation

struct ContentView: View {
    @AppStorage("outputDir") private var outputDir =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Transcripts").path
    /// Langue cible de la traduction .srt (code, ex. "fr").
    @AppStorage("targetLang") private var targetLang = "fr"
    @Environment(\.openWindow) private var openWindow

    @State private var urlText = ""
    @State private var isWorking = false
    @State private var isTranslating = false
    @State private var translationProgress: (done: Int, total: Int) = (0, 0)
    @State private var errorMessage: String?
    @State private var translationNote: String?
    @State private var statusNote: String?
    @State private var result: ExtractionResult?
    @State private var recents: [RecentEntry] = RecentStore.load()
    /// IDs des entrées dont le fichier a disparu du disque. C'est CE state qui
    /// change à la suppression et déclenche le redessin : `entry.exists` lu dans
    /// le body ne suffit pas, car recharger des récents égaux ne réévalue rien.
    @State private var missingIDs: Set<String> = []
    /// Non-nil → déclenche .translationTask (traduction en→cible on-device).
    @State private var translationConfig: TranslationSession.Configuration?

    private var target: TargetLanguage { TargetLanguage.named(targetLang) }

    // Re-vérifie l'existence des fichiers des récents toutes les 5 s : recharger
    // la liste force SwiftUI à réévaluer `entry.exists` (quelques stat(), coût nul).
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Extracteur de sous-titres YouTube")
                .font(.headline)

            HStack {
                TextField("URL de la vidéo YouTube", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isWorking)
                    .onSubmit(startExtraction)
                Button("Extraire", action: startExtraction)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 12) {
                Picker("Traduction :", selection: $targetLang) {
                    ForEach(TargetLanguage.all) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .fixedSize()
                .disabled(isWorking)
                Spacer()
            }
            .font(.caption)

            HStack(spacing: 6) {
                Text("Dossier : \(abbreviatedOutputDir)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Modifier…", action: chooseOutputDir)
                    .font(.caption)
                    .buttonStyle(.link)
                    .disabled(isWorking)
            }

            if isWorking {
                progressRow("Extraction en cours…")
            }
            if isTranslating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(translationLabel).foregroundStyle(.secondary)
                    Spacer()
                    Button("Annuler", action: cancelTranslation)
                        .font(.caption)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let result {
                resultRow(result)
            }

            if !recents.isEmpty {
                Divider()
                recentsSection
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 480)
        .onAppear {
            prefillFromClipboard()
            refreshRecents()
        }
        .onReceive(refreshTimer) { _ in refreshRecents() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refreshRecents() }
        .translationTask(translationConfig) { session in
            await translateAndWriteSRT(session: session)
        }
    }

    // MARK: - Sous-vues

    private var translationLabel: String {
        let (done, total) = translationProgress
        if total > 0 {
            return "Traduction (\(target.name)) — \(done)/\(total) blocs"
        }
        return "Traduction (\(target.name)) en cours…"
    }

    private func progressRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func resultRow(_ result: ExtractionResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.fileURL.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                if let srtURL = result.srtURL {
                    Text(srtURL.lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                } else if let translationNote {
                    Text(translationNote)
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Reveal in Finder") {
                let files = [result.fileURL] + (result.srtURL.map { [$0] } ?? [])
                NSWorkspace.shared.activateFileViewerSelecting(files)
            }
            Button("Copier") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.transcriptText, forType: .string)
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Récents").font(.caption).foregroundStyle(.secondary)
            ForEach(recents.prefix(5)) { entry in
                RecentRow(entry: entry, exists: !missingIDs.contains(entry.id))
            }
            if recents.count > 5 {
                Button("Voir tout l'historique (\(recents.count))") {
                    openWindow(id: "history")
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Mettre à jour yt-dlp", action: updateYtDlp)
                .font(.caption)
                .disabled(isWorking)
            if let statusNote {
                Text(statusNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - Logique

    private var abbreviatedOutputDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return outputDir.hasPrefix(home)
            ? "~" + outputDir.dropFirst(home.count)
            : outputDir
    }

    /// Pré-remplit le champ avec l'URL du presse-papier si c'est un lien YouTube.
    private func prefillFromClipboard() {
        guard urlText.isEmpty,
              let clip = NSPasteboard.general.string(forType: .string)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              clip.contains("youtube.com/") || clip.contains("youtu.be/")
        else { return }
        urlText = clip
    }

    private func startExtraction() {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !isWorking else { return }

        isWorking = true
        errorMessage = nil
        translationNote = nil
        statusNote = nil
        result = nil
        let destination = URL(fileURLWithPath: outputDir)

        Task.detached(priority: .userInitiated) {
            let outcome: Result<ExtractionResult, Error> = Result {
                try Extractor.extract(videoURL: url, outputDir: destination)
            }
            await MainActor.run {
                isWorking = false
                switch outcome {
                case .success(let extraction):
                    result = extraction
                    recordRecent(extraction)
                    // Traduction on-device si vidéo anglaise et cible ≠ anglais.
                    if extraction.sourceIsEnglish, targetLang != "en",
                       !extraction.segments.isEmpty {
                        isTranslating = true
                        startTranslationTask()
                    }
                case .failure(ExtractionError.ytDlpMissing):
                    errorMessage = "yt-dlp est introuvable. Installez-le avec : brew install yt-dlp ffmpeg"
                case .failure:
                    errorMessage = "Cette vidéo est invalide ou ne correspond pas aux critères requis."
                }
            }
        }
    }

    /// (Re)déclenche la tâche liée à .translationTask. Piège SwiftUI : la tâche
    /// ne repart que si la configuration CHANGE. Recréer une config identique
    /// (mêmes langues) est ignoré — la 2e vidéo ne se traduisait jamais.
    /// Même paire de langues → config.invalidate() ; sinon nouvelle config.
    private func startTranslationTask() {
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

    /// Traduit les segments dans la langue cible (framework Translation,
    /// on-device) et écrit le .srt à côté du .txt. Échec non bloquant.
    /// Traité par lots pour afficher la progression et permettre l'annulation
    /// (bouton Annuler → translationConfig = nil → la tâche est annulée).
    private func translateAndWriteSRT(session: TranslationSession) async {
        // NB : ne PAS remettre translationConfig à nil ici — elle reste en place
        // et sera invalidée (config.invalidate()) pour la traduction suivante.
        defer {
            isTranslating = false
            translationProgress = (0, 0)
        }
        // La tâche se déclenche aussi au premier rendu si une config existe
        // déjà : sans extraction en attente, ne rien faire.
        guard isTranslating, let extraction = result else { return }

        do {
            try await session.prepareTranslation()

            // Regroupe en blocs lisibles avant de traduire (évite les cues
            // « flash » de 10 ms des auto-subs YouTube).
            let blocks = VTTParser.groupForSRT(extraction.segments)
            translationProgress = (0, blocks.count)

            var translated: [String] = []
            translated.reserveCapacity(blocks.count)
            let batchSize = 40
            var index = 0
            while index < blocks.count {
                if Task.isCancelled {
                    translationNote = "Traduction annulée."
                    return
                }
                let slice = Array(blocks[index..<min(index + batchSize, blocks.count)])
                let requests = slice.map { TranslationSession.Request(sourceText: $0.text) }
                let responses = try await session.translations(from: requests)
                translated.append(contentsOf: responses.map(\.targetText))
                index += slice.count
                translationProgress = (translated.count, blocks.count)
            }

            let srt = VTTParser.renderSRT(segments: blocks, translatedTexts: translated)
            let srtURL = extraction.fileURL.deletingPathExtension()
                .appendingPathExtension("\(targetLang).srt")
            try srt.write(to: srtURL, atomically: true, encoding: .utf8)
            result?.srtURL = srtURL
            if let updated = result { recordRecent(updated) }
        } catch is CancellationError {
            translationNote = "Traduction annulée."
        } catch {
            translationNote = "Traduction indisponible (\(error.localizedDescription))"
        }
    }

    private func cancelTranslation() {
        // Annule la tâche liée à .translationTask et remet l'UI à zéro.
        translationConfig = nil
        isTranslating = false
        translationProgress = (0, 0)
        translationNote = "Traduction annulée."
    }

    /// Recharge les récents et recalcule quels fichiers manquent sur le disque.
    private func refreshRecents() {
        recents = RecentStore.load()
        missingIDs = Set(recents.filter { !$0.exists }.map(\.id))
    }

    private func recordRecent(_ extraction: ExtractionResult) {
        let entry = RecentEntry(
            title: extraction.fileURL.deletingPathExtension().lastPathComponent,
            txtPath: extraction.fileURL.path,
            srtPath: extraction.srtURL?.path,
            date: Date()
        )
        recents = RecentStore.add(entry)
    }

    private func updateYtDlp() {
        statusNote = "Mise à jour de yt-dlp…"
        Task.detached(priority: .userInitiated) {
            let message = Extractor.updateYtDlp()
            await MainActor.run { statusNote = message }
        }
    }

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: outputDir)
        panel.prompt = "Choisir"
        if panel.runModal() == .OK, let url = panel.url {
            outputDir = url.path
        }
    }
}
