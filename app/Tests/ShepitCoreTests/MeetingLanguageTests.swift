import Testing
@testable import ShepitCore

struct MeetingLanguageTests {
    private func request(_ language: Language) -> TranscriptionRequest {
        TranscriptionRequest(samples: [0], language: language, prompt: "", wantSegments: true)
    }

    private final class Calls: @unchecked Sendable { var languages: [Language] = [] }

    private func run(_ request: TranscriptionRequest, first: Transcript) async throws -> (Transcript, [Language]) {
        let calls = Calls()
        let result = try await MeetingLanguage.transcribe(request) { asked in
            calls.languages.append(asked.language)
            return asked.language == .uk ? Transcript(text: "Ми", segments: [], detectedLanguage: "uk") : first
        }
        return (result, calls.languages)
    }

    @Test func aChunkDetectedAsRussianIsRecognizedAgainAsUkrainian() async throws {
        let (result, languages) = try await run(request(.auto), first: Transcript(text: "Мы", segments: [], detectedLanguage: "ru"))
        #expect(languages == [.auto, .uk])
        #expect(result.text == "Ми")
    }

    @Test func russianOnlyLettersAloneAlsoTriggerTheRetry() async throws {
        let (_, languages) = try await run(request(.auto), first: Transcript(text: "каждый этих", segments: [], detectedLanguage: nil))
        #expect(languages == [.auto, .uk])
    }

    @Test func ukrainianEnglishAndOtherChunksAreKept() async throws {
        // An English chunk over music can come back as "de" or "nn"; forcing Ukrainian would translate it.
        for (text, language) in [("Добрий день, це їхній текст", "uk"), ("Let's sync", "en"), ("Don't run, Max", "de")] {
            let (result, languages) = try await run(request(.auto), first: Transcript(text: text, segments: [], detectedLanguage: language))
            #expect(languages == [.auto])
            #expect(result.text == text)
        }
    }

    @Test func aForcedLanguageIsNeverOverridden() async throws {
        let (_, languages) = try await run(request(.en), first: Transcript(text: "Мы", segments: [], detectedLanguage: "ru"))
        #expect(languages == [.en])
    }
}

struct EnglishPromptTests {
    @Test func englishSpeechGetsTheTermsOnlyPrompt() {
        let request = TranscriptionRequest(samples: [], language: .auto, prompt: "Сьогодні я відкрив pull request. Kubernetes",
                                           wantSegments: true, englishPrompt: "Kubernetes")
        #expect(request.prompt(for: "en") == "Kubernetes")
        #expect(request.prompt(for: "uk") == "Сьогодні я відкрив pull request. Kubernetes")
        #expect(TranscriptionRequest(samples: [], language: .en, prompt: "p", wantSegments: false).prompt(for: "en") == "p")
    }
}
