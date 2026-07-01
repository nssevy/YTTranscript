import Foundation

/// Nettoyage des .vtt YouTube : balises retirées, lignes dupliquées
/// (artefact classique des auto-sous-titres) fusionnées, regroupement
/// en blocs lisibles avec timestamps.
enum VTTParser {
    struct Segment {
        let start: TimeInterval
        var text: String
    }

    struct Chapter {
        let start: TimeInterval
        let title: String
    }

    // MARK: - Parsing

    static func parse(_ vtt: String) -> [Segment] {
        var cues: [Segment] = []
        var currentStart: TimeInterval?
        var currentLines: [String] = []

        func flushCue() {
            if let start = currentStart {
                let text = currentLines.joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    cues.append(Segment(start: start, text: text))
                }
            }
            currentStart = nil
            currentLines = []
        }

        for rawLine in vtt.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.contains("-->") {
                flushCue()
                currentStart = parseTimestamp(String(line.prefix(while: { $0 != " " })))
                continue
            }
            if line.isEmpty {
                flushCue()
                continue
            }
            // En-têtes et métadonnées du format VTT.
            if line.hasPrefix("WEBVTT") || line.hasPrefix("Kind:") || line.hasPrefix("Language:")
                || line.hasPrefix("NOTE") || line.hasPrefix("STYLE") {
                continue
            }
            guard currentStart != nil else { continue } // identifiant de cue, ignoré

            let cleaned = stripTags(line)
            if !cleaned.isEmpty {
                currentLines.append(cleaned)
            }
        }
        flushCue()

        return dedupe(cues)
    }

    /// Retire les balises <c>, <00:00:00.000>, <b>, etc.
    private static func stripTags(_ line: String) -> String {
        line.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Les auto-sous-titres répètent la dernière ligne du cue précédent
    /// (affichage déroulant). On supprime ces répétitions.
    private static func dedupe(_ cues: [Segment]) -> [Segment] {
        var result: [Segment] = []
        var lastText = ""

        for cue in cues {
            var text = cue.text
            if !lastText.isEmpty {
                if text == lastText { continue }
                if text.hasPrefix(lastText) {
                    text = String(text.dropFirst(lastText.count))
                        .trimmingCharacters(in: .whitespaces)
                    if text.isEmpty { continue }
                }
            }
            lastText = cue.text
            result.append(Segment(start: cue.start, text: text))
        }
        return result
    }

    /// "00:01:23.456" ou "01:23.456" → secondes.
    static func parseTimestamp(_ raw: String) -> TimeInterval {
        let parts = raw.split(separator: ":").map { Double($0) ?? 0 }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        default: return 0
        }
    }

    // MARK: - Rendu

    /// Fusionne les cues en blocs d'environ 300 caractères, timestamp au début
    /// de chaque bloc, chapitres insérés à leur position.
    static func render(segments: [Segment], chapters: [Chapter]) -> String {
        var lines: [String] = []
        var remainingChapters = chapters

        var blockStart: TimeInterval = 0
        var blockText = ""

        func flushBlock() {
            guard !blockText.isEmpty else { return }
            lines.append("[\(formatTimestamp(blockStart))] \(blockText)")
            blockText = ""
        }

        for segment in segments {
            // Chapitre atteint → on ferme le bloc courant et on insère le titre.
            while let chapter = remainingChapters.first, segment.start >= chapter.start {
                flushBlock()
                lines.append("")
                lines.append("== \(chapter.title) ==")
                remainingChapters.removeFirst()
            }
            if blockText.isEmpty {
                blockStart = segment.start
                blockText = segment.text
            } else {
                blockText += " " + segment.text
            }
            if blockText.count >= 300 {
                flushBlock()
            }
        }
        flushBlock()

        return lines.joined(separator: "\n") + "\n"
    }

    /// "[mm:ss]" en dessous d'une heure, "[h:mm:ss]" au-delà.
    static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
