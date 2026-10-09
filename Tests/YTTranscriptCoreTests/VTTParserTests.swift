import Testing
@testable import YTTranscriptCore

struct VTTParserTests {
    @Test func parseTimestampHoursMinutesSeconds() {
        #expect(VTTParser.parseTimestamp("00:01:23.456") == 83.456)
    }

    @Test func parseTimestampMinutesSeconds() {
        #expect(VTTParser.parseTimestamp("01:23.456") == 83.456)
    }

    @Test func parseTimestampZero() {
        #expect(VTTParser.parseTimestamp("00:00:00.000") == 0)
    }

    @Test func formatTimestampBelowOneHour() {
        #expect(VTTParser.formatTimestamp(83) == "01:23")
    }

    @Test func formatTimestampAboveOneHour() {
        #expect(VTTParser.formatTimestamp(3723) == "1:02:03")
    }

    @Test func formatSRTTimestamp() {
        #expect(VTTParser.formatSRTTimestamp(83.456) == "00:01:23,456")
    }

    @Test func formatSRTTimestampZero() {
        #expect(VTTParser.formatSRTTimestamp(0) == "00:00:00,000")
    }

    @Test func renderSRTWrapsLongLineAtFortyTwoCharacters() {
        let long = "This video was sponsored by Let's Get Rusty today we cover concepts"
        let wrapped = VTTParser.renderSRT(
            segments: [VTTParser.Segment(start: 0, end: 3, text: long)],
            translatedTexts: [long]
        )
        let lines = wrapped.split(separator: "\n").filter { !$0.contains("-->") && Int($0) == nil }
        #expect(lines.allSatisfy { $0.count <= 42 })
    }

    @Test func renderSRTWrapsIntoAtMostTwoLines() {
        let long = "This video was sponsored by Let's Get Rusty today we cover concepts"
        let wrapped = VTTParser.renderSRT(
            segments: [VTTParser.Segment(start: 0, end: 3, text: long)],
            translatedTexts: [long]
        )
        let lines = wrapped.split(separator: "\n").filter { !$0.contains("-->") && Int($0) == nil }
        #expect(lines.count <= 2)
    }

    @Test func renderSRTWrapLosesNoWord() {
        let long = "This video was sponsored by Let's Get Rusty today we cover concepts"
        let wrapped = VTTParser.renderSRT(
            segments: [VTTParser.Segment(start: 0, end: 3, text: long)],
            translatedTexts: [long]
        )
        let lines = wrapped.split(separator: "\n").filter { !$0.contains("-->") && Int($0) == nil }
        #expect(lines.joined(separator: " ") == long)
    }

    /// Reproduit le motif YouTube : chaque cue reprend la ligne précédente
    /// (affichage déroulant des auto-sous-titres).
    @Test func parseDedupesRollingAutoSubtitleCues() {
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
        let segments = VTTParser.parse(vtt)
        #expect(segments.map(\.text) == ["hello world", "this is a test", "of the parser"])
    }

    @Test func groupForSRTMergesManyShortSegments() {
        let segments = (0..<40).map {
            VTTParser.Segment(start: Double($0), end: Double($0) + 1, text: "word\($0)")
        }
        let groups = VTTParser.groupForSRT(segments)
        #expect(groups.count < segments.count)
    }

    @Test func groupForSRTKeepsBlocksShort() {
        let segments = (0..<40).map {
            VTTParser.Segment(start: Double($0), end: Double($0) + 1, text: "word\($0)")
        }
        let groups = VTTParser.groupForSRT(segments)
        #expect(groups.allSatisfy { $0.text.count <= 84 + 12 })
    }

    @Test func groupForSRTCapsBlockDurationAtSixSeconds() {
        let segments = (0..<40).map {
            VTTParser.Segment(start: Double($0), end: Double($0) + 1, text: "word\($0)")
        }
        let groups = VTTParser.groupForSRT(segments)
        #expect(groups.allSatisfy { $0.end - $0.start <= 6 })
    }

    @Test func groupForSRTStartsAtZero() {
        let segments = (0..<40).map {
            VTTParser.Segment(start: Double($0), end: Double($0) + 1, text: "word\($0)")
        }
        let groups = VTTParser.groupForSRT(segments)
        #expect(groups.first?.start == 0)
    }
}
