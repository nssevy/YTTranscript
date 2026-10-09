import Testing
@testable import YTTranscriptCore

struct ExtractorTests {
    @Test func sanitizeFilenameReplacesForbiddenCharacters() {
        #expect(Extractor.sanitizeFilename("a/b:c?d") == "a b c d")
    }

    @Test func sanitizeFilenameCollapsesRepeatedSpaces() {
        #expect(Extractor.sanitizeFilename("trop    d'espaces") == "trop d'espaces")
    }

    @Test func sanitizeFilenameFallsBackToDefaultWhenEmpty() {
        #expect(Extractor.sanitizeFilename("   ") == "transcript")
    }

    @Test func isPlaylistDetectsPurePlaylistURL() {
        #expect(Extractor.isPlaylist("https://www.youtube.com/playlist?list=PL1"))
    }

    @Test func isPlaylistRejectsVideoOpenedInsidePlaylist() {
        #expect(!Extractor.isPlaylist("https://www.youtube.com/watch?v=abc&list=PL1"))
    }

    @Test func pickTrackPrefersManualTrackInVideoLanguage() {
        let track = Extractor.pickTrack(videoLang: "fr", manual: ["fr", "en"], auto: [])
        #expect(track?.lang == "fr")
        #expect(track?.isAuto == false)
    }

    @Test func pickTrackFallsBackToAutoOriginalLanguage() {
        let track = Extractor.pickTrack(videoLang: "fr", manual: [], auto: ["fr-orig", "en"])
        #expect(track?.lang == "fr-orig")
        #expect(track?.isAuto == true)
    }

    @Test func pickTrackReturnsNilWhenNothingAvailable() {
        #expect(Extractor.pickTrack(videoLang: "fr", manual: [], auto: []) == nil)
    }
}
