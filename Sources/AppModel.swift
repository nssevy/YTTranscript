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
struct RecentEntry: Codable, Identifiable, Hashable {
    let title: String
    let txtPath: String
    let srtPath: String?
    let date: Date
    var id: String { txtPath }

    var txtURL: URL { URL(fileURLWithPath: txtPath) }
    var srtURL: URL? { srtPath.map { URL(fileURLWithPath: $0) } }
    /// Fichiers à sélectionner dans le Finder.
    var finderFiles: [URL] { [txtURL] + (srtURL.map { [$0] } ?? []) }
}

/// Persiste les dernières extractions dans UserDefaults (JSON).
enum RecentStore {
    private static let key = "recentExtractions"
    private static let maxCount = 8

    static func load() -> [RecentEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([RecentEntry].self, from: data)
        else { return [] }
        return entries
    }

    /// Ajoute une entrée en tête, dédoublonne par chemin, borne la taille.
    static func add(_ entry: RecentEntry) -> [RecentEntry] {
        var entries = load().filter { $0.txtPath != entry.txtPath }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(maxCount))
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return entries
    }
}
