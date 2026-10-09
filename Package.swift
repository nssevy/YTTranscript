// swift-tools-version: 6.2
import PackageDescription

// Seule la logique pure (YTTranscriptCore) passe par SwiftPM : c'est elle qui
// a besoin d'être testée en TDD. L'app SwiftUI/AppKit (Sources/YTTranscript)
// dépend de frameworks système (Translation, AppKit) qui ne se résolvent pas
// proprement avec le toolchain Swift autonome utilisé ici (pas de Xcode
// installé — seulement les Command Line Tools). Elle reste buildée par
// build.sh avec le compilateur système, en import-ant YTTranscriptCore
// comme un module compilé séparément. Voir README/CONTRIBUTING pour le détail.
let package = Package(
    name: "YTTranscript",
    targets: [
        .target(
            name: "YTTranscriptCore"
        ),
        .testTarget(
            name: "YTTranscriptCoreTests",
            dependencies: ["YTTranscriptCore"]
        ),
    ]
)
