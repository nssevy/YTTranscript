import SwiftUI
import AppKit

/// Panneau compact de la barre de menus : extraction rapide depuis le
/// presse-papier, aperçu de la file, accès à la fenêtre principale.
struct MenuBarView: View {
    @ObservedObject private var appState = AppState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YTTranscript")
                .font(.headline)

            Button {
                if let clip = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !clip.isEmpty {
                    appState.add(urlsText: clip)
                }
            } label: {
                Label("Extraire le presse-papier", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            if !appState.queue.isEmpty {
                Divider()
                // Les 4 derniers éléments, les plus récents en premier.
                ForEach(appState.queue.suffix(4).reversed()) { item in
                    HStack(spacing: 6) {
                        statusIcon(item)
                        Text(item.displayTitle)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if item.status == .translating, let progress = item.progress {
                            Text("\(progress.done)/\(progress.total)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Ouvrir l'app") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quitter") {
                    NSApp.terminate(nil)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 280)
    }

    @ViewBuilder
    private func statusIcon(_ item: QueueItem) -> some View {
        switch item.status {
        case .pending, .expanding:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .extracting, .translating:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .duplicate:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
