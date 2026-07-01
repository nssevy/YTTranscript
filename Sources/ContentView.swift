import SwiftUI
import AppKit
import Translation

struct ContentView: View {
    @AppStorage("outputDir") private var outputDir =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Transcripts").path

    @State private var urlText = ""
    @State private var isWorking = false
    @State private var isTranslating = false
    @State private var errorMessage: String?
    @State private var translationNote: String?
    @State private var result: ExtractionResult?
    /// Non-nil → déclenche .translationTask (traduction en→fr on-device).
    @State private var translationConfig: TranslationSession.Configuration?

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
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Extraction en cours…")
                        .foregroundStyle(.secondary)
                }
            }

            if isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Traduction française en cours…")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let result {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.fileURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let srtURL = result.srtURL {
                            Text(srtURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else if let translationNote {
                            Text(translationNote)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Button("Reveal in Finder") {
                        let files = [result.fileURL] + (result.srtURL.map { [$0] } ?? [])
                        NSWorkspace.shared.activateFileViewerSelecting(files)
                    }
                    Button("Copier") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(result.transcriptText, forType: .string)
                    }
                }
            }
        }
        .padding(20)
        .translationTask(translationConfig) { session in
            await translateAndWriteSRT(session: session)
        }
    }

    private var abbreviatedOutputDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return outputDir.hasPrefix(home)
            ? "~" + outputDir.dropFirst(home.count)
            : outputDir
    }

    private func startExtraction() {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !isWorking else { return }

        isWorking = true
        errorMessage = nil
        translationNote = nil
        result = nil
        translationConfig = nil
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
                    if extraction.sourceIsEnglish, !extraction.segments.isEmpty {
                        // Déclenche la traduction on-device (voir .translationTask).
                        isTranslating = true
                        translationConfig = TranslationSession.Configuration(
                            source: Locale.Language(identifier: "en"),
                            target: Locale.Language(identifier: "fr")
                        )
                    }
                case .failure(ExtractionError.ytDlpMissing):
                    errorMessage = "yt-dlp est introuvable. Installez-le avec : brew install yt-dlp ffmpeg"
                case .failure:
                    errorMessage = "Cette vidéo est invalide ou ne correspond pas aux critères requis."
                }
            }
        }
    }

    /// Traduit les segments en français (framework Translation, on-device)
    /// et écrit le .srt à côté du .txt. Échec non bloquant.
    private func translateAndWriteSRT(session: TranslationSession) async {
        defer {
            isTranslating = false
            translationConfig = nil
        }
        guard let extraction = result else { return }

        do {
            // Télécharge le modèle en→fr au premier usage (dialogue système).
            try await session.prepareTranslation()

            // Regroupe en blocs lisibles avant de traduire (évite les cues
            // « flash » de 10 ms des auto-subs YouTube).
            let blocks = VTTParser.groupForSRT(extraction.segments)
            let requests = blocks.map {
                TranslationSession.Request(sourceText: $0.text)
            }
            let responses = try await session.translations(from: requests)
            let translated = responses.map(\.targetText)

            let srt = VTTParser.renderSRT(
                segments: blocks,
                translatedTexts: translated
            )
            let srtURL = extraction.fileURL.deletingPathExtension()
                .appendingPathExtension("fr.srt")
            try srt.write(to: srtURL, atomically: true, encoding: .utf8)
            result?.srtURL = srtURL
        } catch {
            translationNote = "Traduction française indisponible (\(error.localizedDescription))"
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
