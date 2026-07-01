import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("outputDir") private var outputDir =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Transcripts").path

    @State private var urlText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var result: ExtractionResult?

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
                    Text(result.fileURL.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
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
                case .failure(ExtractionError.ytDlpMissing):
                    errorMessage = "yt-dlp est introuvable. Installez-le avec : brew install yt-dlp ffmpeg"
                case .failure:
                    errorMessage = "Cette vidéo est invalide ou ne correspond pas aux critères requis."
                }
            }
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
