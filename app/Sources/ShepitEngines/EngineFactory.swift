import Foundation
import ShepitCore

public enum EngineFactory {
    public static func make(_ choice: EngineChoice) throws -> any SpeechEngine {
        switch choice.engine {
        case .whispercpp:
            return WhisperCppEngine(model: choice.model)
        case .whisperkit:
            return WhisperKitEngine(model: choice.model)
        case .parakeet:
            return ParakeetEngine(model: choice.model)
        case .apple:
            guard #available(macOS 26, *) else {
                throw EngineError.unavailableOnThisMac("Apple Speech requires macOS 26 or later")
            }
            return AppleSpeechEngine()
        }
    }
}
