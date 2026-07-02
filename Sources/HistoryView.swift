import SwiftUI
import AppKit

/// Miniature vidéo (ou repli icône) commune aux lignes récents/historique.
struct EntryThumbnail: View {
    let entry: RecentEntry
    let exists: Bool
    var width: CGFloat = 64

    var body: some View {
        if let urlString = entry.thumbnailURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .saturation(exists ? 1 : 0)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: width, height: width * 9 / 16)
                .overlay {
                    Image(systemName: "doc.text")
                        .foregroundStyle(exists ? Color.secondary : Color.red)
                }
        }
    }
}

/// Ligne compacte (écran principal) : miniature + titre barré/rouge si supprimé.
struct RecentRow: View {
    let entry: RecentEntry
    // Passé par le parent (recalculé à chaque refresh) : sans ce paramètre,
    // SwiftUI mémoïse la ligne tant que `entry` est identique et n'affiche
    // jamais la suppression du fichier.
    let exists: Bool
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            EntryThumbnail(entry: entry, exists: exists, width: 48)
            Text(entry.title)
                .font(.callout)
                .strikethrough(!exists)
                .foregroundStyle(exists ? Color.primary : Color.red)
                .lineLimit(1)
                .truncationMode(.middle)
            if !exists {
                Text("supprimé")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button("Ouvrir") {
                NSWorkspace.shared.activateFileViewerSelecting(entry.finderFiles)
            }
            .font(.caption)
            .buttonStyle(.link)
            .disabled(!exists)
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle")
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .help("Retirer de l'historique")
            }
        }
    }
}

/// Ligne enrichie (écran historique) : miniature, chaîne, durée, date.
struct HistoryRow: View {
    let entry: RecentEntry
    let exists: Bool
    /// Extrait du transcript contenant le terme recherché, si pertinent.
    let snippet: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .strikethrough(!exists)
                    .foregroundStyle(exists ? Color.primary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let snippet {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                }
                if !exists {
                    Text("supprimé")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Button("Ouvrir") {
                NSWorkspace.shared.activateFileViewerSelecting(entry.finderFiles)
            }
            .font(.caption)
            .buttonStyle(.link)
            .disabled(!exists)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Retirer de l'historique")
        }
        .padding(.vertical, 2)
    }

    private var thumbnail: some View {
        EntryThumbnail(entry: entry, exists: exists)
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let channel = entry.channel { parts.append(channel) }
        if let duration = entry.duration, duration > 0 {
            parts.append(VTTParser.formatTimestamp(duration.rounded(.down)))
        }
        parts.append(entry.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

/// Écran d'historique affiché DANS la fenêtre principale, avec recherche
/// plein texte (titres + contenu des .txt) et tri.
struct HistoryView: View {
    /// Retour à l'écran principal.
    let onBack: () -> Void

    enum SortOrder: String, CaseIterable, Identifiable {
        case date = "Date"
        case title = "Titre"
        var id: String { rawValue }
    }

    @State private var entries: [RecentEntry] = RecentStore.load()
    /// Voir ContentView : ce state change à la suppression d'un fichier
    /// et force le redessin (des entrées égales ne suffisent pas).
    @State private var missingIDs: Set<String> = []
    @State private var confirmClear = false
    @State private var query = ""
    @State private var sortOrder: SortOrder = .date
    /// Résultats de la recherche plein texte : id → extrait correspondant.
    @State private var contentMatches: [String: String] = [:]
    @State private var searchTask: Task<Void, Never>?

    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    /// `reload` : redécode le JSON (ouverture, suppression). Sinon simple
    /// re-vérification d'existence des fichiers (pas de décodage toutes les 5 s).
    private func refresh(reload: Bool = false) {
        if reload { entries = RecentStore.load() }
        missingIDs = Set(entries.filter { !$0.exists }.map(\.id))
    }

    /// Entrées filtrées par la recherche (titre OU contenu) puis triées.
    private var visibleEntries: [RecentEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var filtered = entries
        if !trimmed.isEmpty {
            filtered = entries.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || contentMatches[$0.id] != nil
            }
        }
        switch sortOrder {
        case .date:
            return filtered.sorted { $0.date > $1.date }
        case .title:
            return filtered.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Label("Retour", systemImage: "chevron.left")
                }
                Text("Historique")
                    .font(.headline)
                Spacer()
                Picker("Tri", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher dans les titres et les transcripts…", text: $query)
                    .textFieldStyle(.roundedBorder)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if visibleEntries.isEmpty {
                Text(query.isEmpty ? "Aucune extraction pour le moment."
                                   : "Aucun résultat pour « \(query) ».")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleEntries) { entry in
                        HistoryRow(
                            entry: entry,
                            exists: !missingIDs.contains(entry.id),
                            snippet: contentMatches[entry.id]
                        ) {
                            entries = RecentStore.remove(entry.id)
                            AppState.shared.refreshRecents(reload: true)
                        }
                    }
                }
                .listStyle(.inset)

                HStack {
                    Text("\(visibleEntries.count) élément\(visibleEntries.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Vider tout l'historique", role: .destructive) {
                        confirmClear = true
                    }
                    .font(.caption)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 400)
        // Rafraîchit l'état d'existence à l'ouverture, au focus et toutes les 5 s.
        .onAppear { refresh(reload: true) }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(refreshTimer) { _ in
            guard NSApp.isActive else { return }
            refresh()
        }
        .onChange(of: query) { _, newQuery in
            scheduleContentSearch(newQuery)
        }
        .confirmationDialog(
            "Vider tout l'historique ?",
            isPresented: $confirmClear
        ) {
            Button("Vider", role: .destructive) {
                RecentStore.clear()
                refresh(reload: true)
                AppState.shared.refreshRecents(reload: true)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les fichiers sur le disque ne seront pas supprimés.")
        }
    }

    /// Recherche plein texte dans les .txt, en tâche de fond avec un léger
    /// debounce (annule la recherche précédente à chaque frappe).
    private func scheduleContentSearch(_ rawQuery: String) {
        searchTask?.cancel()
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            contentMatches = [:]
            return
        }
        let candidates = entries.filter { $0.exists }
        searchTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }

            var matches: [String: String] = [:]
            for entry in candidates {
                if Task.isCancelled { return }
                guard let content = try? String(contentsOfFile: entry.txtPath, encoding: .utf8),
                      let range = content.range(of: trimmed, options: [.caseInsensitive])
                else { continue }
                // Extrait : la ligne contenant la première occurrence.
                let line = content[content.lineRange(for: range)]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                matches[entry.id] = String(line.prefix(140))
            }
            let found = matches
            await MainActor.run { contentMatches = found }
        }
    }
}
