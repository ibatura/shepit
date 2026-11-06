import Darwin
import Foundation
import ShepitCore
import ShepitEngines
import Speech

public enum Bench {
    public static func run(
        arguments: [String],
        engineFactory: (EngineChoice) throws -> any SpeechEngine = EngineFactory.make,
        output: (String) -> Void = { print($0) }
    ) async -> Int32 {
        do {
            let options = try parse(arguments)
            guard let model = options.model else { throw EngineError.loadFailed("no model specified") }
            let choice = EngineChoice(engine: options.engine, model: model)
            let engine = try engineFactory(choice)
            if let error = await engine.capabilities.check(options.language) {
                throw error
            }

            let start = ContinuousClock.now
            try await engine.load()
            let loadSeconds = durationSeconds(start.duration(to: .now))
            output(jsonLine([
                "event": "load",
                "engine": options.engine.rawValue,
                "model": model,
                "seconds": loadSeconds,
                "residentMB": residentMemoryMB()
            ]))

            for file in options.files {
                let samples = try AudioFile.load(URL(fileURLWithPath: file))
                let request = TranscriptionRequest(
                    samples: samples,
                    language: options.language,
                    prompt: options.prompt,
                    wantSegments: false,
                    englishPrompt: options.englishPrompt
                )
                let recognitionStart = ContinuousClock.now
                let transcript = try await engine.transcribe(request)
                output(jsonLine([
                    "event": "result",
                    "file": file,
                    "audioSeconds": Double(samples.count) / 16_000,
                    "seconds": durationSeconds(recognitionStart.duration(to: .now)),
                    "text": transcript.text,
                    "language": transcript.detectedLanguage as Any? ?? NSNull()
                ]))
            }
            await engine.unload()
            return 0
        } catch {
            output(jsonLine(["event": "error", "message": String(describing: error)]))
            return 1
        }
    }
}

/// `Shepit apple-assets <uk|en> [--install]`: reports Apple speech asset status; installs only when asked.
@available(macOS 26, *)
public enum AppleAssets {
    public static func run(arguments: [String], output: (String) -> Void = { print($0) }) async -> Int32 {
        guard let first = arguments.first, let language = Language(rawValue: first), language != .auto,
              arguments.dropFirst().allSatisfy({ $0 == "--install" }) else {
            output(jsonLine(["event": "error", "message": "usage: Shepit apple-assets <uk|en> [--install]"]))
            return 2
        }
        guard let module = await AppleSpeechEngine.module(for: language) else {
            output(jsonLine(["event": "assets", "language": language.rawValue, "status": "unsupported"]))
            return 1
        }
        do {
            if arguments.contains("--install"), let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        } catch {
            output(jsonLine(["event": "error", "message": String(describing: error)]))
            return 1
        }
        output(jsonLine([
            "event": "assets",
            "language": language.rawValue,
            "module": String(describing: type(of: module)),
            "status": String(describing: await AppleSpeechEngine.assetStatus(for: language, module: module))
        ]))
        return 0
    }
}

private struct BenchOptions {
    var engine: EngineID
    var model: String?
    var language: Language = .uk
    var prompt = ""
    var englishPrompt: String?
    var files: [String] = []
}

private func parse(_ arguments: [String]) throws -> BenchOptions {
    guard arguments.count >= 2 else {
        throw EngineError.loadFailed("usage: Shepit bench --engine <id> [--model <name>] [--language uk|en|auto] [--prompt <text>] [--english-prompt <text>] <file>...")
    }
    var options = BenchOptions(engine: .whispercpp)
    var foundEngine = false
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--engine" || argument == "--model" || argument == "--language" || argument == "--prompt" || argument == "--english-prompt" {
            guard index + 1 < arguments.count else {
                throw EngineError.loadFailed("missing value for \(argument)")
            }
            let value = arguments[index + 1]
            switch argument {
            case "--engine":
                guard let engine = EngineID(rawValue: value) else {
                    throw EngineError.loadFailed("unknown engine: \(value)")
                }
                options.engine = engine
                foundEngine = true
            case "--model":
                options.model = value
            case "--language":
                guard let language = Language(rawValue: value) else {
                    throw EngineError.loadFailed("unknown language: \(value)")
                }
                options.language = language
            case "--english-prompt":
                options.englishPrompt = value
            default:
                options.prompt = value
            }
            index += 2
        } else if argument.hasPrefix("-") {
            throw EngineError.loadFailed("unknown option: \(argument)")
        } else {
            options.files.append(argument)
            index += 1
        }
    }
    guard foundEngine else { throw EngineError.loadFailed("--engine is required") }
    guard !options.files.isEmpty else { throw EngineError.loadFailed("at least one audio file is required") }
    if options.model == nil { options.model = ModelCatalog.models(for: options.engine).first }
    guard let model = options.model else { throw EngineError.loadFailed("no default model for \(options.engine.rawValue)") }
    options.model = model
    return options
}

private func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
}

private func jsonLine(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys]),
          let line = String(data: data, encoding: .utf8) else {
        return "{\"event\":\"error\",\"message\":\"Could not encode output\"}"
    }
    return line
}

func residentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
}
