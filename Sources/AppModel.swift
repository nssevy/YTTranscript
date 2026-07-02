import Foundation

/// Langues cibles proposées pour la traduction .srt.
/// Le code sert au framework Translation ET au suffixe du fichier (.<code>.srt).
struct TargetLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    static let all: [TargetLanguage] = [
        .init(code: "fr", name: "Français"),
        .init(code: "es", name: "Espagnol"),
        .init(code: "de", name: "Allemand"),
        .init(code: "it", name: "Italien"),
        .init(code: "pt", name: "Portugais"),
        .init(code: "nl", name: "Néerlandais"),
        .init(code: "ja", name: "Japonais"),
        .init(code: "ko", name: "Coréen"),
        .init(code: "zh", name: "Chinois"),
        .init(code: "ru", name: "Russe"),
    ]

    static func named(_ code: String) -> TargetLanguage {
        all.first { $0.code == code } ?? all[0]
    }
}

/// Une extraction passée, pour la liste des récents.
/// Les champs optionnels manquent sur les entrées créées par d'anciennes
/// versions : l'UI doit prévoir un repli.
struct RecentEntry: Codable, Identifiable, Hashable {
    let title: String
    let txtPath: String
    let srtPath: String?
    let date: Date
    /// ID YouTube (ex. "dQw4w9WgXcQ"), optionnel pour les entrées historiques.
    var videoID: String?
    // Métadonnées enrichies (historique v2).
    var channel: String?
    var duration: Double?
    var thumbnailURL: String?
    var id: String { txtPath }

    var txtURL: URL { URL(fileURLWithPath: txtPath) }
    var srtURL: URL? { srtPath.map { URL(fileURLWithPath: $0) } }
    /// Fichiers à sélectionner dans le Finder.
    var finderFiles: [URL] { [txtURL] + (srtURL.map { [$0] } ?? []) }

    /// Le fichier .txt existe-t-il encore sur le disque ? (false = supprimé)
    var exists: Bool { FileManager.default.fileExists(atPath: txtPath) }
}

/// Extrait l'ID vidéo d'une URL YouTube (watch?v=, youtu.be/, shorts/, embed/).
/// nil si non reconnu — dans ce cas la détection de doublon est simplement ignorée.
func youtubeVideoID(from url: String) -> String? {
    let patterns = [
        "[?&]v=([A-Za-z0-9_-]{6,})",
        "youtu\\.be/([A-Za-z0-9_-]{6,})",
        "/(?:shorts|embed|live)/([A-Za-z0-9_-]{6,})",
    ]
    for pattern in patterns {
        if let match = url.range(of: pattern, options: .regularExpression) {
            let id = String(url[match])
                .replacingOccurrences(of: "^.*[=/]", with: "", options: .regularExpression)
            if !id.isEmpty { return id }
        }
    }
    return nil
}

/// Persiste les dernières extractions dans UserDefaults (JSON).
enum RecentStore {
    private static let key = "recentExtractions"
    private static let maxCount = 200

    static func load() -> [RecentEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([RecentEntry].self, from: data)
        else { return [] }
        return entries
    }

    private static func save(_ entries: [RecentEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Ajoute une entrée en tête, dédoublonne par chemin, borne la taille.
    static func add(_ entry: RecentEntry) -> [RecentEntry] {
        var entries = load().filter { $0.txtPath != entry.txtPath }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(maxCount))
        save(entries)
        return entries
    }

    /// Retire une entrée de l'historique (n'efface pas les fichiers du disque).
    static func remove(_ id: String) -> [RecentEntry] {
        let entries = load().filter { $0.id != id }
        save(entries)
        return entries
    }

    /// Vide tout l'historique (ne touche pas aux fichiers du disque).
    static func clear() {
        save([])
    }

    /// Réécrit les chemins de l'historique après déplacement du dossier de
    /// sortie : préfixe `oldDir` remplacé par `newDir`.
    static func rebase(from oldDir: String, to newDir: String) -> [RecentEntry] {
        func moved(_ path: String) -> String {
            path.hasPrefix(oldDir + "/")
                ? newDir + path.dropFirst(oldDir.count)
                : path
        }
        let entries = load().map { entry in
            RecentEntry(
                title: entry.title,
                txtPath: moved(entry.txtPath),
                srtPath: entry.srtPath.map(moved),
                date: entry.date,
                videoID: entry.videoID,
                channel: entry.channel,
                duration: entry.duration,
                thumbnailURL: entry.thumbnailURL
            )
        }
        save(entries)
        return entries
    }
}
