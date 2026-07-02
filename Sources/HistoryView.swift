import SwiftUI
import AppKit

/// Une ligne d'historique : titre (barré + rouge si supprimé du disque),
/// bouton Ouvrir (désactivé si absent) et éventuel bouton Retirer.
struct RecentRow: View {
    let entry: RecentEntry
    // Passé par le parent (recalculé à chaque refresh) : sans ce paramètre,
    // SwiftUI mémoïse la ligne tant que `entry` est identique et n'affiche
    // jamais la suppression du fichier.
    let exists: Bool
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(exists ? Color.secondary : Color.red)
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

/// Fenêtre séparée listant tout l'historique des extractions.
struct HistoryView: View {
    @State private var entries: [RecentEntry] = RecentStore.load()
    /// Voir ContentView.missingIDs : ce state change à la suppression d'un
    /// fichier et force le redessin (des entrées égales ne suffisent pas).
    @State private var missingIDs: Set<String> = []
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private func refresh() {
        entries = RecentStore.load()
        missingIDs = Set(entries.filter { !$0.exists }.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Historique des extractions")
                    .font(.headline)
                Spacer()
                Text("\(entries.count) élément\(entries.count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Text("Aucune extraction pour le moment.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        RecentRow(entry: entry, exists: !missingIDs.contains(entry.id)) {
                            entries = RecentStore.remove(entry.id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
        // Rafraîchit l'état d'existence à l'ouverture, au focus et toutes les 5 s.
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(refreshTimer) { _ in refresh() }
    }
}
