import Testing
@testable import YTTranscriptCore

struct AppModelTests {
    @Test func youtubeVideoIDFromWatchURL() {
        #expect(youtubeVideoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func youtubeVideoIDFromShortURLWithParameter() {
        #expect(youtubeVideoID(from: "https://youtu.be/dQw4w9WgXcQ?t=42") == "dQw4w9WgXcQ")
    }

    @Test func youtubeVideoIDFromShortsURL() {
        #expect(youtubeVideoID(from: "https://www.youtube.com/shorts/abc123XYZ_-") == "abc123XYZ_-")
    }

    @Test func youtubeVideoIDWhenVIsSecondParameter() {
        #expect(youtubeVideoID(from: "https://www.youtube.com/watch?list=PL1&v=XJC5WB2Bwrc") == "XJC5WB2Bwrc")
    }

    @Test func youtubeVideoIDReturnsNilForUnrecognizedURL() {
        #expect(youtubeVideoID(from: "https://example.com/pas-youtube") == nil)
    }

    @Test func targetLanguageNamedReturnsMatchingLanguage() {
        #expect(TargetLanguage.named("fr").name == "Français")
    }

    @Test func targetLanguageNamedFallsBackToFirstWhenUnknown() {
        #expect(TargetLanguage.named("xx").code == TargetLanguage.all[0].code)
    }
}
