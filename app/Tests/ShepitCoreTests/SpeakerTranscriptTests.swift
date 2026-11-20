import Foundation
import Testing
@testable import ShepitCore

// Import names design §4: the speakers of a Teams or Zoom .vtt. Made-up files.
struct SpeakerTranscriptTests {
    private typealias Cue = SpeakerTranscript.Cue

    @Test func teamsGivesTheVoiceTagsName() throws {
        let file = """
            WEBVTT

            0f7c1e2a-1111-4c2d-9e8f-0123456789ab/12-0
            00:00:06.059 --> 00:00:08.859
            <v Olena K.>Good morning, everyone.</v>

            0f7c1e2a-1111-4c2d-9e8f-0123456789ab/13-0
            00:01:02.000 --> 01:00:05.500
            <v Marko D. (Guest)>First line,
            and the second: still Marko.</v>

            0f7c1e2a-1111-4c2d-9e8f-0123456789ab/14-0
            00:02:00.000 --> 00:02:01.000
            <v  Olena K. >no closing tag

            00:03:00.000 --> 00:03:01.000
            <v.loud.slow Marko D.>A voice with classes.</v>
            """
        #expect(try SpeakerTranscript.cues(file) == [
            Cue(start: 6.059, end: 8.859, speaker: "Olena K."),
            Cue(start: 62, end: 3605.5, speaker: "Marko D. (Guest)"),
            Cue(start: 120, end: 121, speaker: "Olena K."),
            Cue(start: 180, end: 181, speaker: "Marko D."),
        ])
    }

    @Test func zoomGivesWhatComesBeforeTheFirstColon() throws {
        let file = """
            WEBVTT

            1
            00:00:54.450 --> 00:00:55.980
            Olena K.: Right, let's start: the plan.

            2
            00:00:56.000 --> 00:00:58.000
            Marko D.: Yes.

            3
            00:00:58.000 --> 00:00:59.000
            no name here
            """
        #expect(try SpeakerTranscript.cues(file) == [
            Cue(start: 54.45, end: 55.98, speaker: "Olena K."),
            Cue(start: 56, end: 58, speaker: "Marko D."),
        ])
    }

    @Test func aBOMCRLFShortTimesSettingsAndNotesAreRead() throws {
        let file = "\u{FEFF}WEBVTT - made by a meeting app\r\n\r\nNOTE a comment\r\nover two lines\r\n\r\n"
            + "12:04.320 --> 12:07.950 align:start position:0%\r\n<v Olena K.>Hello</v>\r\n"
        #expect(try SpeakerTranscript.cues(file) == [Cue(start: 724.32, end: 727.95, speaker: "Olena K.")])
    }

    @Test func aFileThatIsNotWebVTTOrHasNoSpeakersIsRefused() {
        #expect(throws: SpeakerTranscript.Problem.notWebVTT) { try SpeakerTranscript.cues("") }
        #expect(throws: SpeakerTranscript.Problem.notWebVTT) { try SpeakerTranscript.cues("1\n00:00:01.000 --> 00:00:02.000\nOlena: Hi\n") }
        #expect(throws: SpeakerTranscript.Problem.noSpeakers) { try SpeakerTranscript.cues("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello\n") }
        #expect(SpeakerTranscript.Problem.noSpeakers.localizedDescription == "This transcript has no speaker names.")
        #expect(SpeakerTranscript.Problem.notWebVTT.localizedDescription == "This isn't a WebVTT transcript.")
    }

    /// Zoom's captions file has no names, but a few lines of text have a colon.
    @Test func colonsInAFewCaptionsAreNotSpeakers() {
        let captions = (0..<10).map { "00:00:0\($0).000 --> 00:00:0\($0).900\nJust words, line \($0)." }
        let file = "WEBVTT\n\n" + (captions + ["00:00:10.000 --> 00:00:11.000\nThe thing is: it works."]).joined(separator: "\n\n")
        #expect(throws: SpeakerTranscript.Problem.noSpeakers) { try SpeakerTranscript.cues(file) }
    }
}
