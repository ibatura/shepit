@preconcurrency import AVFoundation
import Foundation
import ShepitCore
import Speech

/// Apple's on-device recognizer. SpeechTranscriber has no Ukrainian (macOS 26.4), so a language it
/// doesn't support falls back to DictationTranscriber, which does.
@available(macOS 26, *)
public actor AppleSpeechEngine: SpeechEngine {
    public let choice = EngineChoice(engine: .apple, model: "")
    private var loaded = false

    public init() {}

    public var capabilities: EngineCapabilities {
        get async {
            var forcible: Set<Language> = []
            for language in [Language.uk, .en] where await Self.module(for: language) != nil {
                forcible.insert(language)
            }
            return EngineCapabilities(supportsPrompt: true, forcibleLanguages: forcible, detectsLanguage: false, givesSegmentTimes: true)
        }
    }

    public var isLoaded: Bool { loaded }

    // Assets are per language, so they are checked in transcribe(); there is nothing to load up front.
    public func load() async throws { loaded = true }

    public func unload() async { loaded = false }

    public func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        guard let module = await Self.module(for: request.language) else {
            throw EngineError.languageNotSupported(request.language)
        }
        guard await Self.assetStatus(for: request.language, module: module) == .installed else {
            throw EngineError.modelMissing(
                "Apple speech assets for \(request.language.rawValue) are not installed — run: Shepit apple-assets \(request.language.rawValue) --install")
        }
        let results: Task<[Segment], any Error>
        switch module {
        case let transcriber as SpeechTranscriber:
            results = Self.collect(transcriber) { String($0.text.characters) }
        case let transcriber as DictationTranscriber:
            results = Self.collect(transcriber) { String($0.text.characters) }
        default:
            throw EngineError.loadFailed("unexpected speech module")
        }
        defer { results.cancel() }
        guard !request.samples.isEmpty else { return Transcript(text: "", segments: [], detectedLanguage: nil) }
        do {
            let analyzer = SpeechAnalyzer(modules: [module])
            let terms = request.prompt.split(separator: ", ").map(String.init).filter { !$0.isEmpty }
            if !terms.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = terms
                try await analyzer.setContext(context)
            }
            let buffer = try await Self.buffer(request.samples, for: module)
            let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            continuation.yield(AnalyzerInput(buffer: buffer))
            continuation.finish()
            if let end = try await analyzer.analyzeSequence(input) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let segments = try await results.value
            let text = segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return Transcript(text: text, segments: request.wantSegments ? segments : [], detectedLanguage: nil)
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.recognitionFailed("Apple speech failed: \(error)")
        }
    }

    /// The module that handles this language, or nil when neither recognizer supports it.
    public static func module(for language: Language) async -> (any SpeechModule)? {
        let locale: Locale
        switch language {
        case .uk: locale = Locale(identifier: "uk-UA")
        case .en: locale = Locale(identifier: "en-US")
        case .auto: return nil
        }
        let id = locale.identifier(.bcp47)
        if await SpeechTranscriber.supportedLocales.contains(where: { $0.identifier(.bcp47) == id }) {
            return SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
        }
        if await DictationTranscriber.supportedLocales.contains(where: { $0.identifier(.bcp47) == id }) {
            return DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
        }
        return nil
    }

    /// Asset status for the module that handles `language`.
    public static func assetStatus(for language: Language, module: any SpeechModule) async -> AssetInventory.Status {
        // Status is per process: installed assets read as "supported" until this process reserves the locale.
        // Reserving downloads nothing.
        if let locale = (module as? any LocaleDependentSpeechModule)?.selectedLocales.first {
            _ = try? await AssetInventory.reserve(locale: locale)
        }
        return await AssetInventory.status(forModules: [module])
    }

    private static func collect<M: SpeechModule>(
        _ module: M, text: @escaping @Sendable (M.Result) -> String
    ) -> Task<[Segment], any Error> {
        Task {
            var segments: [Segment] = []
            for try await result in module.results where result.isFinal {
                segments.append(Segment(text: text(result), start: result.range.start.seconds, end: result.range.end.seconds))
            }
            return segments
        }
    }

    private static func buffer(_ samples: [Float], for module: any SpeechModule) async throws -> AVAudioPCMBuffer {
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            throw EngineError.recognitionFailed("could not allocate audio buffer")
        }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]), target != source else {
            return input
        }
        guard let converter = AVAudioConverter(from: source, to: target),
              let output = AVAudioPCMBuffer(
                pcmFormat: target,
                frameCapacity: AVAudioFrameCount(Double(samples.count) * target.sampleRate / 16_000) + 1024) else {
            throw EngineError.recognitionFailed("could not convert audio to \(target)")
        }
        nonisolated(unsafe) var consumed = false // convert(to:) calls the block synchronously
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let conversionError { throw EngineError.recognitionFailed("audio conversion failed: \(conversionError)") }
        guard status != .error else { throw EngineError.recognitionFailed("audio conversion failed") }
        return output
    }
}
