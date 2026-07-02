import SwiftUI
import AppKit
import Translation

/// Écrans affichés dans la fenêtre unique de l'app.
enum Screen {
    case main, history, settings
}

struct ContentView: View {
    @AppStorage("autoExtractOnPaste") private var autoExtractOnPaste = false
    @AppStorage("notifyOnDone") private var notifyOnDone = true

    @ObservedObject private var appState = AppState.shared

    @State private var screen: Screen = .main
    @State private var urlText = ""

    // Re-vérifie l'existence des fichiers des récents toutes les 5 s : recharger
    // la liste force SwiftUI à réévaluer l'existence (quelques stat(), coût nul).
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        // Les modificateurs (timer, translationTask…) restent sur le Group :
        // la traduction continue même sur les écrans historique/paramètres.
        Group {
            switch screen {
            case .main:
                mainScreen
            case .history:
                HistoryView(onBack: { screen = .main })
            case .settings:
                SettingsView(onBack: { screen = .main })
            }
        }
        .frame(minWidth: 480)
        .onAppear {
            prefillFromClipboard()
            appState.refreshRecents()
            if notifyOnDone { Notifier.requestPermission() }
        }
        .onReceive(refreshTimer) { _ in appState.refreshRecents() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in appState.refreshRecents() }
        .translationTask(appState.translationConfig) { session in
            await appState.runTranslation(session: session)
        }
    }

    // MARK: - Écran principal

    private var mainScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Extracteur de sous-titres YouTube")
                .font(.headline)

            HStack {
                TextField("URL de vidéo ou de playlist YouTube", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button("Coller", action: pasteFromClipboard)
                    .help("Coller le contenu du presse-papier")
                Button("Extraire", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !appState.queue.isEmpty {
                queueSection
            }

            if !appState.recents.isEmpty {
                Divider()
                recentsSection
            }

            Divider()
            footer
        }
        .padding(20)
    }

    // MARK: - File d'attente

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("File d'attente").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if appState.queue.contains(where: {
                    [.done, .failed, .duplicate].contains($0.status)
                }) {
                    Button("Effacer terminés", action: appState.clearFinished)
                        .font(.caption)
                        .buttonStyle(.link)
                }
            }
            ForEach(appState.queue) { item in
                QueueRow(item: item)
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Récents").font(.caption).foregroundStyle(.secondary)
            ForEach(appState.recents.prefix(5)) { entry in
                RecentRow(entry: entry,
                          exists: !appState.missingIDs.contains(entry.id))
            }
            if appState.recents.count > 5 {
                Button("Voir tout l'historique (\(appState.recents.count))") {
                    screen = .history
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                screen = .history
            } label: {
                Label("Historique", systemImage: "clock.arrow.circlepath")
            }
            .font(.caption)
            Button {
                screen = .settings
            } label: {
                Label("Paramètres", systemImage: "gearshape")
                    .overlay(alignment: .topTrailing) {
                        if appState.ytDlpUpdateAvailable {
                            Circle().fill(.red).frame(width: 6, height: 6)
                                .offset(x: 6, y: -4)
                        }
                    }
            }
            .font(.caption)
            Spacer()
        }
    }

    // MARK: - Logique

    private func submit() {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appState.add(urlsText: text)
        urlText = ""
    }

    /// Remplace le champ URL par le contenu du presse-papier (bouton Coller).
    /// Si l'extraction auto est activée et que c'est une URL YouTube, lance direct.
    private func pasteFromClipboard() {
        guard let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty
        else { return }
        urlText = clip
        if autoExtractOnPaste, youtubeVideoID(from: clip) != nil || Extractor.isPlaylist(clip) {
            submit()
        }
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
}

// MARK: - Ligne de la file d'attente

struct QueueRow: View {
    let item: QueueItem
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }
            }

            Spacer()
            actions
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String? {
        switch item.status {
        case .pending: return "En attente"
        case .expanding: return "Lecture de la playlist…"
        case .extracting: return "Extraction en cours…"
        case .translating:
            if let progress = item.progress, progress.total > 0 {
                return "Traduction — \(progress.done)/\(progress.total) blocs"
            }
            return "Traduction en cours…"
        case .done: return item.note ?? item.result?.srtURL?.lastPathComponent
        case .failed: return item.errorText
        case .duplicate: return "Cette vidéo a déjà été extraite."
        }
    }

    private var subtitleColor: Color {
        switch item.status {
        case .failed: return .red
        case .duplicate: return .orange
        case .done: return item.note == nil ? .secondary : .orange
        default: return .secondary
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending, .expanding:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .extracting, .translating:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .duplicate:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch item.status {
        case .done:
            if let result = item.result {
                Button("Ouvrir") {
                    let files = [result.fileURL] + (result.srtURL.map { [$0] } ?? [])
                    NSWorkspace.shared.activateFileViewerSelecting(files)
                }
                .font(.caption)
                Button("Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.transcriptText, forType: .string)
                }
                .font(.caption)
            }
        case .translating:
            Button("Annuler") { appState.cancelTranslation(item.id) }
                .font(.caption)
        case .duplicate, .failed:
            Button("Extraire quand même") { appState.forceExtract(item.id) }
                .font(.caption)
            Button {
                appState.removeItem(item.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        case .pending:
            Button {
                appState.removeItem(item.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        default:
            EmptyView()
        }
    }
}
