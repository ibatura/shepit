import Foundation

/// With the language on auto, Whisper sometimes takes Ukrainian speech for Russian (the first real call
/// had 7 such lines in 45 minutes). Such a chunk is recognized again as Ukrainian. Only Russian: an English
/// chunk with music can be detected as anything, and forcing Ukrainian on it translates it (Test1, 2026-10-30).
public enum MeetingLanguage {
    /// Letters Russian has and Ukrainian doesn't.
    static let russianOnly: Set<Character> = ["ы", "э", "ъ", "ё", "Ы", "Э", "Ъ", "Ё"]

    public static func needsUkrainian(_ transcript: Transcript, asked: Language) -> Bool {
        guard asked == .auto else { return false }
        if transcript.detectedLanguage == "ru" { return true }
        return transcript.text.contains(where: russianOnly.contains)
    }

    public static func transcribe(_ request: TranscriptionRequest,
                                  run: (TranscriptionRequest) async throws -> Transcript) async throws -> Transcript {
        let first = try await run(request)
        guard needsUkrainian(first, asked: request.language) else { return first }
        var again = request
        again.language = .uk
        return try await run(again)
    }
}
