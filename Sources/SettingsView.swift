import SwiftUI
import AppKit

/// Écran Paramètres, affiché dans la fenêtre principale (comme l'historique).
struct SettingsView: View {
    let onBack: () -> Void

    @AppStorage("outputDir") private var outputDir =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Transcripts").path
    @AppStorage("targetLang") private var targetLang = "fr"
    @AppStorage("autoTranslate") private var autoTranslate = true
    @AppStorage("srtLineWidth") private var srtLineWidth = VTTParser.defaultSRTLineWidth
    @AppStorage("autoExtractOnPaste") private var autoExtractOnPaste = false
    @AppStorage("notifyOnDone") private var notifyOnDone = true

    @State private var moveNote: (String, Bool)?
    @State private var updateNote: String?
    @State private var ytDlpVersion: String?
    @State private var isUpdating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onBack) {
                    Label("Retour", systemImage: "chevron.left")
                }
                Text("Paramètres")
                    .font(.headline)
                Spacer()
            }

            Form {
                Section("Extraction") {
                    LabeledContent("Dossier de sortie") {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(abbreviatedOutputDir)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack {
                                Button("Modifier…", action: chooseOutputDir)
                                    .help("Changer le dossier des prochaines extractions (ne déplace rien)")
                                Button("Déplacer…", action: moveOutputDir)
                                    .help("Déplacer le dossier et son contenu")
                            }
                        }
                    }
                    if let moveNote {
                        Text(moveNote.0)
                            .font(.caption)
                            .foregroundStyle(moveNote.1 ? Color.green : Color.orange)
                    }
                    Toggle("Extraire automatiquement quand une URL YouTube est collée",
                           isOn: $autoExtractOnPaste)
                }

                Section("Traduction") {
                    Toggle("Traduire automatiquement les vidéos en anglais",
                           isOn: $autoTranslate)
                    Picker("Langue cible", selection: $targetLang) {
                        ForEach(TargetLanguage.all) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .disabled(!autoTranslate)
                    Picker("Longueur des sous-titres (.srt)", selection: $srtLineWidth) {
                        Text("Compacts (32 car./ligne)").tag(32)
                        Text("Standards (42 car./ligne)").tag(42)
                        Text("Larges (50 car./ligne)").tag(50)
                    }
                    .disabled(!autoTranslate)
                }

                Section("Notifications") {
                    Toggle("Notifier à la fin (.txt prêt, puis .srt traduit)",
                           isOn: $notifyOnDone)
                        .onChange(of: notifyOnDone) { _, enabled in
                            if enabled { Notifier.requestPermission() }
                        }
                }

                Section("Maintenance") {
                    LabeledContent("yt-dlp") {
                        HStack {
                            Text(ytDlpVersion ?? "version inconnue")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Mettre à jour", action: updateYtDlp)
                                .disabled(isUpdating)
                        }
                    }
                    if isUpdating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Mise à jour en cours…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let updateNote {
                        Text(updateNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 460)
        .onAppear(perform: loadYtDlpVersion)
    }

    // MARK: - Logique

    private var abbreviatedOutputDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return outputDir.hasPrefix(home)
            ? "~" + outputDir.dropFirst(home.count)
            : outputDir
    }

    private func loadYtDlpVersion() {
        Task.detached(priority: .utility) {
            let version = Extractor.ytDlpVersion()
            await MainActor.run { ytDlpVersion = version }
        }
    }

    private func updateYtDlp() {
        isUpdating = true
        updateNote = nil
        Task.detached(priority: .userInitiated) {
            let message = Extractor.updateYtDlp()
            let version = Extractor.ytDlpVersion()
            await MainActor.run {
                isUpdating = false
                updateNote = message
                ytDlpVersion = version
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
            moveNote = nil
        }
    }

    /// Déplace le dossier de sortie et tout son contenu, puis met à jour la
    /// config et les chemins de l'historique.
    /// - Dossier choisi vide → son contenu y est déplacé directement.
    /// - Dossier choisi non vide → le dossier actuel (ex. "Transcripts") y est
    ///   déplacé entier, comme dans le Finder.
    private func moveOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choisissez où déplacer le dossier des transcripts."
        panel.prompt = "Déplacer ici"
        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        let source = URL(fileURLWithPath: outputDir)
        let fm = FileManager.default

        guard chosen.path != source.path else {
            moveNote = ("C'est déjà l'emplacement actuel.", false)
            return
        }
        guard !chosen.path.hasPrefix(source.path + "/") else {
            moveNote = ("Impossible : la destination est à l'intérieur du dossier actuel.", false)
            return
        }

        do {
            let chosenContents = ((try? fm.contentsOfDirectory(atPath: chosen.path)) ?? [])
                .filter { $0 != ".DS_Store" }
            let destination: URL
            if chosenContents.isEmpty {
                // Dossier vide : il devient le nouveau dossier de sortie.
                destination = chosen
                for item in (try fm.contentsOfDirectory(atPath: source.path))
                    where item != ".DS_Store" {
                    try fm.moveItem(
                        at: source.appendingPathComponent(item),
                        to: destination.appendingPathComponent(item)
                    )
                }
            } else {
                // Dossier non vide : on y déplace le dossier actuel entier.
                destination = chosen.appendingPathComponent(source.lastPathComponent)
                guard !fm.fileExists(atPath: destination.path) else {
                    moveNote = ("Impossible : « \(destination.lastPathComponent) » existe déjà à cet endroit.", false)
                    return
                }
                try fm.moveItem(at: source, to: destination)
            }

            let oldDir = source.path
            outputDir = destination.path
            _ = RecentStore.rebase(from: oldDir, to: destination.path)
            moveNote = ("Dossier déplacé.", true)
        } catch {
            moveNote = ("Échec du déplacement : \(error.localizedDescription)", false)
        }
    }
}
