import Foundation

/// Langues cibles proposées pour la traduction .srt.
/// Le code sert au framework Translation ET au suffixe du fichier (.<code>.srt).
public struct TargetLanguage: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    public static let all: [TargetLanguage] = [
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

    public static func named(_ code: String) -> TargetLanguage {
        all.first { $0.code == code } ?? all[0]
    }
}

/// Une extraction passée, pour la liste des récents.
/// Les champs optionnels manquent sur les entrées créées par d'anciennes
/// versions : l'UI doit prévoir un repli.
public struct RecentEntry: Codable, Identifiable, Hashable, Sendable {
    public let title: String
    public let txtPath: String
    public let srtPath: String?
    public let date: Date
    /// ID YouTube (ex. "dQw4w9WgXcQ"), optionnel pour les entrées historiques.
    public var videoID: String?
    // Métadonnées enrichies (historique v2).
    public var channel: String?
    public var duration: Double?
    public var thumbnailURL: String?
    public var id: String { txtPath }

    public init(
        title: String,
        txtPath: String,
        srtPath: String?,
        date: Date,
        videoID: String? = nil,
        channel: String? = nil,
        duration: Double? = nil,
        thumbnailURL: String? = nil
    ) {
        self.title = title
        self.txtPath = txtPath
        self.srtPath = srtPath
        self.date = date
        self.videoID = videoID
        self.channel = channel
        self.duration = duration
        self.thumbnailURL = thumbnailURL
    }

    public var txtURL: URL { URL(fileURLWithPath: txtPath) }
    public var srtURL: URL? { srtPath.map { URL(fileURLWithPath: $0) } }
    /// Fichiers à sélectionner dans le Finder.
    public var finderFiles: [URL] { [txtURL] + (srtURL.map { [$0] } ?? []) }

    /// Le fichier .txt existe-t-il encore sur le disque ? (false = supprimé)
    public var exists: Bool { FileManager.default.fileExists(atPath: txtPath) }
}

/// Extrait l'ID vidéo d'une URL YouTube (watch?v=, youtu.be/, shorts/, embed/).
/// nil si non reconnu — dans ce cas la détection de doublon est simplement ignorée.
public func youtubeVideoID(from url: String) -> String? {
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
public enum RecentStore {
    private static let key = "recentExtractions"
    private static let maxCount = 200

    public static func load() -> [RecentEntry] {
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
    public static func add(_ entry: RecentEntry) -> [RecentEntry] {
        var entries = load().filter { $0.txtPath != entry.txtPath }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(maxCount))
        save(entries)
        return entries
    }

    /// Retire une entrée de l'historique (n'efface pas les fichiers du disque).
    public static func remove(_ id: String) -> [RecentEntry] {
        let entries = load().filter { $0.id != id }
        save(entries)
        return entries
    }

    /// Vide tout l'historique (ne touche pas aux fichiers du disque).
    public static func clear() {
        save([])
    }

    /// Réécrit les chemins de l'historique après déplacement du dossier de
    /// sortie : préfixe `oldDir` remplacé par `newDir`.
    public static func rebase(from oldDir: String, to newDir: String) -> [RecentEntry] {
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
