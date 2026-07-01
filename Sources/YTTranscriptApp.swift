import SwiftUI

@main
struct YTTranscriptApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 480, maxWidth: 560)
        }
        .windowResizability(.contentSize)

        // Fenêtre secondaire de l'historique (ouverte via openWindow("history")).
        Window("Historique", id: "history") {
            HistoryView()
        }
    }
}
