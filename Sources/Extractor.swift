import Foundation

enum ExtractionError: Error {
    /// yt-dlp est absent du système.
    case ytDlpMissing
    /// Toute autre cause (pas de sous-titres, URL erronée, vidéo privée, réseau…).
    /// Le spec impose un message unique pour ces cas.
    case invalidVideo
}

struct ExtractionResult {
    let fileURL: URL
    let transcriptText: String
}

struct Extractor {
    static let ytDlpPath = "/opt/homebrew/bin/yt-dlp"

    /// Extrait les sous-titres de la vidéo et écrit le .txt dans `outputDir`.
    /// Synchrone et bloquant : à appeler hors du main thread.
    static func extract(videoURL: String, outputDir: URL) throws -> ExtractionResult {
        guard FileManager.default.isExecutableFile(atPath: ytDlpPath) else {
            throw ExtractionError.ytDlpMissing
        }

        // 1. Métadonnées + liste des pistes de sous-titres disponibles.
        let (status, jsonOut, _) = runProcess(ytDlpPath, [
            "--dump-json", "--no-playlist", "--skip-download", videoURL,
        ])
        guard status == 0,
              let jsonData = jsonOut.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            throw ExtractionError.invalidVideo
        }

        let title = info["title"] as? String ?? "Sans titre"
        let channel = (info["channel"] as? String) ?? (info["uploader"] as? String) ?? "Inconnue"
        let duration = info["duration"] as? Double ?? 0
        let pageURL = info["webpage_url"] as? String ?? videoURL
        let videoLang = info["language"] as? String
        let chapters = parseChapters(info["chapters"])

        // 2. Choix de la piste : manuels prioritaires, langue d'origine puis anglais.
        let manualLangs = trackLanguages(info["subtitles"])
        let autoLangs = trackLanguages(info["automatic_captions"])
        guard let track = pickTrack(videoLang: videoLang, manual: manualLangs, auto: autoLangs) else {
            throw ExtractionError.invalidVideo
        }

        // 3. Téléchargement de la piste .vtt seule (jamais la vidéo).
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YTTranscript-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let subFlag = track.isAuto ? "--write-auto-subs" : "--write-subs"
        let (dlStatus, _, _) = runProcess(ytDlpPath, [
            "--skip-download", "--no-playlist", subFlag,
            "--sub-langs", track.lang, "--sub-format", "vtt",
            "-o", tmpDir.appendingPathComponent("sub").path,
            videoURL,
        ])
        let vttFiles = (try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "vtt" } ?? []
        guard dlStatus == 0, let vttFile = vttFiles.first,
              let vttContent = try? String(contentsOf: vttFile, encoding: .utf8)
        else {
            throw ExtractionError.invalidVideo
        }

        // 4. Nettoyage du VTT et assemblage du .txt final.
        let segments = VTTParser.parse(vttContent)
        guard !segments.isEmpty else { throw ExtractionError.invalidVideo }

        var text = """
        Titre : \(title)
        Chaîne : \(channel)
        Durée : \(formatDurationHHMM(duration))
        URL : \(pageURL)

        """
        text += VTTParser.render(segments: segments, chapters: chapters)

        // 5. Écriture du fichier.
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let fileURL = outputDir.appendingPathComponent(sanitizeFilename(title) + ".txt")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        return ExtractionResult(fileURL: fileURL, transcriptText: text)
    }

    // MARK: - Choix de piste

    struct Track {
        let lang: String
        let isAuto: Bool
    }

    /// Manuels prioritaires ; langue d'origine de la vidéo, repli anglais,
    /// puis n'importe quelle piste manuelle disponible.
    static func pickTrack(videoLang: String?, manual: [String], auto: [String]) -> Track? {
        var candidates: [String] = []
        if let lang = videoLang { candidates.append(lang) }
        candidates.append("en")

        for lang in candidates {
            if let match = bestMatch(lang, in: manual) { return Track(lang: match, isAuto: false) }
        }
        if let first = manual.first { return Track(lang: first, isAuto: false) }
        for lang in candidates {
            // Les auto-sous-titres YouTube exposent la piste d'origine en "xx-orig".
            if let match = bestMatch(lang + "-orig", in: auto) { return Track(lang: match, isAuto: true) }
            if let match = bestMatch(lang, in: auto) { return Track(lang: match, isAuto: true) }
        }
        return nil
    }

    /// Correspondance exacte, sinon par préfixe ("en" matche "en-US").
    private static func bestMatch(_ lang: String, in available: [String]) -> String? {
        if available.contains(lang) { return lang }
        let base = lang.split(separator: "-").first.map(String.init) ?? lang
        return available.first { $0 == base || $0.hasPrefix(base + "-") }
    }

    private static func trackLanguages(_ raw: Any?) -> [String] {
        guard let dict = raw as? [String: Any] else { return [] }
        return dict.keys.sorted()
    }

    private static func parseChapters(_ raw: Any?) -> [VTTParser.Chapter] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { entry in
            guard let start = entry["start_time"] as? Double,
                  let title = entry["title"] as? String else { return nil }
            return VTTParser.Chapter(start: start, title: title)
        }.sorted { $0.start < $1.start }
    }

    // MARK: - Utilitaires

    /// Durée pour l'en-tête : "mm:ss", ou "h:mm:ss" au-delà d'une heure
    /// (même format que les timestamps du transcript).
    static func formatDurationHHMM(_ seconds: Double) -> String {
        // Troncature (pas d'arrondi) pour coller à la durée affichée par YouTube.
        VTTParser.formatTimestamp(seconds.rounded(.down))
    }

    /// Retire les caractères interdits dans un nom de fichier macOS/Finder.
    static func sanitizeFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\0")
        let cleaned = name.components(separatedBy: forbidden).joined(separator: " ")
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(120))
        return limited.isEmpty ? "transcript" : limited
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, "", "\(error)")
        }
        // Lire les pipes AVANT waitUntilExit pour éviter un deadlock
        // quand la sortie dépasse la taille du buffer du pipe.
        let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: outData ?? Data(), encoding: .utf8) ?? "",
            String(data: errData ?? Data(), encoding: .utf8) ?? ""
        )
    }
}
