import Foundation

/// Nettoyage des .vtt YouTube : balises retirées, lignes dupliquées
/// (artefact classique des auto-sous-titres) fusionnées, regroupement
/// en blocs lisibles avec timestamps.
enum VTTParser {
    struct Segment {
        let start: TimeInterval
        var end: TimeInterval
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
        var currentEnd: TimeInterval = 0
        var currentLines: [String] = []

        func flushCue() {
            if let start = currentStart {
                let text = currentLines.joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    cues.append(Segment(start: start, end: currentEnd, text: text))
                }
            }
            currentStart = nil
            currentLines = []
        }

        for rawLine in vtt.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.contains("-->") {
                flushCue()
                let parts = line.components(separatedBy: "-->")
                currentStart = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces))
                let endRaw = parts.count > 1
                    ? parts[1].trimmingCharacters(in: .whitespaces)
                    : ""
                currentEnd = parseTimestamp(String(endRaw.prefix(while: { $0 != " " })))
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
                if text == lastText {
                    // Cue purement répétée : on prolonge l'affichage du précédent.
                    if !result.isEmpty { result[result.count - 1].end = cue.end }
                    continue
                }
                if text.hasPrefix(lastText) {
                    text = String(text.dropFirst(lastText.count))
                        .trimmingCharacters(in: .whitespaces)
                    if text.isEmpty {
                        if !result.isEmpty { result[result.count - 1].end = cue.end }
                        continue
                    }
                }
            }
            // On mémorise le texte RÉELLEMENT émis (pas le cue joint complet) :
            // le report du cue suivant est toujours cette dernière ligne émise,
            // ce qui permet au strip de préfixe de retirer le doublon déroulant.
            lastText = text
            result.append(Segment(start: cue.start, end: cue.end, text: text))
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

    /// Largeur de ligne .srt par défaut : 2 lignes de ~42 caractères (norme lisible).
    static let defaultSRTLineWidth = 42

    /// Regroupe les segments bruts en blocs courts, lisibles à l'écran.
    /// Les auto-subs YouTube produisent des cues qui se chevauchent et durent
    /// parfois 10 ms (« flash »). On fusionne jusqu'à 2 lignes de `lineWidth`
    /// caractères / une fin de phrase, borne dure à 6 s.
    static func groupForSRT(_ segments: [Segment],
                            lineWidth: Int = defaultSRTLineWidth) -> [Segment] {
        let srtMaxChars = lineWidth * 2
        var groups: [Segment] = []
        for segment in segments {
            if var last = groups.last {
                let merged = Segment(
                    start: last.start,
                    end: max(last.end, segment.end),
                    text: last.text + " " + segment.text
                )
                let duration = merged.end - merged.start
                let endsSentence = last.text.hasSuffix(".") || last.text.hasSuffix("?")
                    || last.text.hasSuffix("!")
                // On coupe dès que le bloc est plein ou en fin de phrase.
                if merged.text.count > srtMaxChars || duration >= 6 || endsSentence {
                    groups.append(segment)
                } else {
                    last = merged
                    groups[groups.count - 1] = last
                }
            } else {
                groups.append(segment)
            }
        }
        return groups
    }

    /// Fichier .srt à partir des blocs regroupés et de leurs textes traduits
    /// (même ordre, même nombre). Timestamps d'origine conservés.
    static func renderSRT(segments: [Segment], translatedTexts: [String],
                          lineWidth: Int = defaultSRTLineWidth) -> String {
        var blocks: [String] = []
        for (index, segment) in segments.enumerated() {
            let text = index < translatedTexts.count ? translatedTexts[index] : segment.text
            // Fin manquante ou incohérente → 2 s minimum d'affichage.
            let end = segment.end > segment.start + 0.2 ? segment.end : segment.start + 2
            blocks.append("""
            \(index + 1)
            \(formatSRTTimestamp(segment.start)) --> \(formatSRTTimestamp(end))
            \(wrapLines(text, width: lineWidth))
            """)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Replie un texte en lignes de `width` caractères max, sans couper un mot.
    private static func wrapLines(_ text: String, width: Int) -> String {
        let words = text.split(separator: " ")
        var lines: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\n")
    }

    /// "HH:MM:SS,mmm" (format SRT).
    static func formatSRTTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let millis = Int((seconds - Double(total)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d",
                      total / 3600, (total % 3600) / 60, total % 60, millis)
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
