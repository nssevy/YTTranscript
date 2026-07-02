import Foundation

// Harnais de tests minimal (pas de XCTest, build via swiftc — voir test.sh).
// Chaque `check` échoue bruyamment et fait sortir le process en code 1.

var failures = 0

func check(_ condition: Bool, _ label: String,
           file: StaticString = #file, line: UInt = #line) {
    if condition {
        print("  ✓ \(label)")
    } else {
        failures += 1
        print("  ✗ \(label)  (\(file):\(line))")
    }
}

func checkEqual<T: Equatable>(_ got: T, _ expected: T, _ label: String,
                              file: StaticString = #file, line: UInt = #line) {
    check(got == expected, "\(label) — attendu \(expected), obtenu \(got)", file: file, line: line)
}

@main
struct Tests {
    static func main() {
        testTimestamps()
        testWrap()
        testDedupeRolling()
        testGroupForSRT()
        testSanitizeFilename()
        testYoutubeVideoID()

        print("")
        if failures == 0 {
            print("Tous les tests passent.")
        } else {
            print("\(failures) test(s) en échec.")
            exit(1)
        }
    }

    static func testTimestamps() {
        print("Timestamps")
        checkEqual(VTTParser.parseTimestamp("00:01:23.456"), 83.456, "parse hh:mm:ss")
        checkEqual(VTTParser.parseTimestamp("01:23.456"), 83.456, "parse mm:ss")
        checkEqual(VTTParser.parseTimestamp("00:00:00.000"), 0, "parse zéro")
        checkEqual(VTTParser.formatTimestamp(83), "01:23", "format < 1h")
        checkEqual(VTTParser.formatTimestamp(3723), "1:02:03", "format >= 1h")
        checkEqual(VTTParser.formatSRTTimestamp(83.456), "00:01:23,456", "format srt")
        checkEqual(VTTParser.formatSRTTimestamp(0), "00:00:00,000", "format srt zéro")
    }

    static func testWrap() {
        print("Repli des lignes (.srt)")
        let long = "This video was sponsored by Let's Get Rusty today we cover concepts"
        let wrapped = VTTParser.renderSRT(
            segments: [VTTParser.Segment(start: 0, end: 3, text: long)],
            translatedTexts: [long]
        )
        let lines = wrapped.split(separator: "\n").filter { !$0.contains("-->") && Int($0) == nil }
        check(lines.allSatisfy { $0.count <= 42 }, "aucune ligne > 42 caractères")
        check(lines.count <= 2, "au plus 2 lignes")
        let rejoined = lines.joined(separator: " ")
        checkEqual(rejoined, long, "aucun mot perdu")
    }

    static func testDedupeRolling() {
        print("Déduplication déroulante (auto-subs)")
        // Reproduit le motif YouTube : chaque cue reprend la ligne précédente.
        let vtt = """
        WEBVTT
        Kind: captions

        00:00:00.000 --> 00:00:02.000
        hello world

        00:00:02.000 --> 00:00:02.010
        hello world

        00:00:02.010 --> 00:00:04.000
        hello world
        this is a test

        00:00:04.000 --> 00:00:04.010
        this is a test

        00:00:04.010 --> 00:00:06.000
        this is a test
        of the parser
        """
        let segs = VTTParser.parse(vtt)
        let texts = segs.map(\.text)
        checkEqual(texts, ["hello world", "this is a test", "of the parser"], "3 segments propres sans doublon")
    }

    static func testGroupForSRT() {
        print("Regroupement pour .srt")
        // Beaucoup de très courts segments → doivent fusionner en blocs bornés.
        var segs: [VTTParser.Segment] = []
        for i in 0..<40 {
            segs.append(VTTParser.Segment(start: Double(i), end: Double(i) + 1, text: "word\(i)"))
        }
        let groups = VTTParser.groupForSRT(segs)
        check(groups.count < segs.count, "les segments sont fusionnés")
        check(groups.allSatisfy { $0.text.count <= 84 + 12 }, "chaque bloc reste court")
        check(groups.allSatisfy { $0.end - $0.start <= 6 }, "chaque bloc dure au plus ~6 s")
        // Couverture temporelle continue.
        checkEqual(groups.first?.start, 0, "commence à 0")
    }

    static func testYoutubeVideoID() {
        print("ID vidéo YouTube")
        checkEqual(youtubeVideoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
                   "dQw4w9WgXcQ", "watch?v=")
        checkEqual(youtubeVideoID(from: "https://youtu.be/dQw4w9WgXcQ?t=42"),
                   "dQw4w9WgXcQ", "youtu.be avec paramètre")
        checkEqual(youtubeVideoID(from: "https://www.youtube.com/shorts/abc123XYZ_-"),
                   "abc123XYZ_-", "shorts")
        checkEqual(youtubeVideoID(from: "https://www.youtube.com/watch?list=PL1&v=XJC5WB2Bwrc"),
                   "XJC5WB2Bwrc", "v= en second paramètre")
        checkEqual(youtubeVideoID(from: "https://example.com/pas-youtube"),
                   nil, "URL non reconnue → nil")
    }

    static func testSanitizeFilename() {
        print("Nettoyage du nom de fichier")
        checkEqual(Extractor.sanitizeFilename("a/b:c?d"), "a b c d", "caractères interdits remplacés")
        checkEqual(Extractor.sanitizeFilename("trop    d'espaces"), "trop d'espaces", "espaces multiples réduits")
        checkEqual(Extractor.sanitizeFilename("   "), "transcript", "vide → défaut")
    }
}
