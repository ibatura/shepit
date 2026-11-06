import Darwin
import Foundation
import ShepitCore
import whisper

public actor WhisperCppEngine: SpeechEngine {
    public let choice: EngineChoice
    private let vadModel: URL
    private var context: OpaquePointer?

    public init(model: String, vadModel: URL = ModelCatalog.vadModel) {
        choice = EngineChoice(engine: .whispercpp, model: model)
        self.vadModel = vadModel
    }

    public var capabilities: EngineCapabilities {
        EngineCapabilities(supportsPrompt: true, forcibleLanguages: [.uk, .en], detectsLanguage: true, givesSegmentTimes: true)
    }

    public var isLoaded: Bool { context != nil }

    public func load() throws {
        guard context == nil else { return }
        let path = ModelCatalog.folder(for: choice)!.path
        guard ModelCatalog.isDownloaded(choice) else { throw EngineError.modelMissing(path) }
        // whisper_full fails without the VAD model; refuse before paying for the big model load.
        guard FileManager.default.fileExists(atPath: vadModel.path) else { throw EngineError.modelMissing(vadModel.path) }
        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let loaded = whisper_init_from_file_with_params(path, params) else {
            throw EngineError.loadFailed("whisper.cpp could not load \(path)")
        }
        context = loaded
    }

    public func unload() {
        if let context { whisper_free(context) }
        context = nil
    }

    public func transcribe(_ request: TranscriptionRequest) throws -> Transcript {
        try load()
        guard let context else { throw EngineError.loadFailed("whisper.cpp context missing") }
        // Auto means Ukrainian or English, decided per part: free detection took Ukrainian for Russian and
        // English over music for something else, and one language for a whole phrase dropped or translated
        // the other one when a speaker switched mid-phrase (Task 11).
        let parts = request.language == .auto
            ? try languageParts(context, request.samples, leaning: request.leaning)
            : [LanguagePart(range: 0..<request.samples.count, language: request.language.rawValue)]
        var segments: [Segment] = []
        for part in parts {
            let offset = Double(part.range.lowerBound) / 16_000
            segments += try run(context, Array(request.samples[part.range]), language: part.language,
                                prompt: request.prompt(for: part.language), segments: request.wantSegments)
                .map { Segment(text: $0.text, start: $0.start + offset, end: $0.end + offset) }
        }
        let text = segments.map(\.text).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        let languages = parts.map(\.language).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return Transcript(text: text, segments: request.wantSegments ? segments : [], detectedLanguage: languages.joined(separator: "+"))
    }

    private func run(_ context: OpaquePointer, _ samples: [Float], language: String, prompt promptText: String, segments: Bool) throws -> [Segment] {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.temperature = 0
        params.no_timestamps = !segments
        params.n_threads = performanceCores()
        params.vad = true
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        let status = language.withCString { language in
            promptText.withCString { prompt in
                vadModel.path.withCString { vadPath in
                    params.language = language
                    params.initial_prompt = promptText.isEmpty ? nil : prompt
                    params.vad_model_path = vadPath
                    return samples.withUnsafeBufferPointer {
                        whisper_full(context, params, $0.baseAddress, Int32($0.count))
                    }
                }
            }
        }
        guard status == 0 else { throw EngineError.recognitionFailed("whisper_full returned \(status)") }
        return (0..<whisper_full_n_segments(context)).map { index in
            Segment(
                text: String(cString: whisper_full_get_segment_text(context, index)),
                start: Double(whisper_full_get_segment_t0(context, index)) * 0.01,
                end: Double(whisper_full_get_segment_t1(context, index)) * 0.01
            )
        }
    }

    /// The phrase cut at short pauses into pieces, each "uk" or "en"; neighbours with one language are joined.
    /// Whisper's detection on the whole phrase can't be the shortcut: it gave Ukrainian at 97–99% for phrases
    /// that were half English. Costs one detection per piece: a 23 s phrase takes 7 s instead of 2 s.
    private func languageParts(_ context: OpaquePointer, _ samples: [Float], leaning: String?) throws -> [LanguagePart] {
        var parts: [LanguagePart] = []
        for piece in LanguagePart.pieces(samples) {
            let language = try ukrainianOrEnglish(context, Array(samples[piece]), leaning: leaning)
            if let last = parts.last, last.language == language {
                parts[parts.count - 1].range = last.range.lowerBound..<piece.upperBound
            } else {
                parts.append(LanguagePart(range: piece, language: language))
            }
        }
        return parts.isEmpty ? [LanguagePart(range: 0..<samples.count, language: "uk")] : parts
    }

    /// Whisper's language detection (first 30 s) decided by `LanguageChoice`: Ukrainian taken for Russian
    /// (or real Russian) comes out in Ukrainian rather than translated into English.
    private func ukrainianOrEnglish(_ context: OpaquePointer, _ samples: [Float], leaning: String?) throws -> String {
        guard !samples.isEmpty else { return "uk" }
        let threads = performanceCores()
        let mel = samples.withUnsafeBufferPointer { whisper_pcm_to_mel(context, $0.baseAddress, Int32($0.count), threads) }
        guard mel == 0 else { throw EngineError.recognitionFailed("whisper_pcm_to_mel returned \(mel)") }
        var probabilities = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let top = whisper_lang_auto_detect(context, 0, threads, &probabilities)
        guard top >= 0 else { throw EngineError.recognitionFailed("whisper language detection failed") }
        let codes = ["en", "uk", "ru", "be"]
        let probability = Dictionary(uniqueKeysWithValues: codes.map { code in
            let id = Int(whisper_lang_id(code))
            return (code, probabilities.indices.contains(id) ? probabilities[id] : 0)
        })
        return LanguageChoice.pick(top: top == whisper_lang_id("en") ? "en" : "other", probabilities: probability, leaning: leaning)
    }
}

private func performanceCores() -> Int32 {
    var count: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0) == 0, count > 0 else { return 4 }
    return count
}
