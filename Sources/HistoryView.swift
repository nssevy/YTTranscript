import SwiftUI
import AppKit

/// Une ligne d'historique : titre (barré + rouge si supprimé du disque),
/// bouton Ouvrir (désactivé si absent) et éventuel bouton Retirer.
struct RecentRow: View {
    let entry: RecentEntry
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.exists ? "doc.text" : "doc.text")
                .foregroundStyle(entry.exists ? Color.secondary : Color.red)
            Text(entry.title)
                .font(.callout)
                .strikethrough(!entry.exists)
                .foregroundStyle(entry.exists ? Color.primary : Color.red)
                .lineLimit(1)
                .truncationMode(.middle)
            if !entry.exists {
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
            .disabled(!entry.exists)
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
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

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
                        RecentRow(entry: entry) {
                            entries = RecentStore.remove(entry.id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
        // Rafraîchit l'état d'existence au focus et toutes les 5 s.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            entries = RecentStore.load()
        }
        .onReceive(refreshTimer) { _ in entries = RecentStore.load() }
    }
}
