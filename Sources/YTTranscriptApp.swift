import SwiftUI

@main
struct YTTranscriptApp: App {
    @AppStorage("menuBarIcon") private var menuBarIcon = true

    init() {
        Notifier.configure(delegate: AppState.shared)
        if UserDefaults.standard.object(forKey: "clipboardWatch") as? Bool ?? false {
            AppState.shared.setClipboardWatch(enabled: true)
        }
        if UserDefaults.standard.object(forKey: "autoCheckYtDlp") as? Bool ?? true {
            AppState.shared.checkYtDlpUpdate()
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 480, maxWidth: 560)
        }
        .windowResizability(.contentSize)

        // Icône barre de menus : extraction rapide sans ouvrir la fenêtre.
        MenuBarExtra("YTTranscript", systemImage: "captions.bubble",
                     isInserted: $menuBarIcon) {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
