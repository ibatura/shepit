@preconcurrency import AVFoundation
import Foundation
import ShepitCore

private final class AudioInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var provided = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !provided else {
            status.pointee = .endOfStream
            return nil
        }
        provided = true
        status.pointee = .haveData
        return buffer
    }
}

public enum AudioFile {
    public static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw EngineError.loadFailed("Could not convert audio file to 16 kHz mono Float32")
        }
        guard file.length > 0 else { return [] }
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw EngineError.loadFailed("Could not allocate audio input buffer")
        }
        try file.read(into: input)
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw EngineError.loadFailed("Could not allocate converted audio buffer")
        }
        converter.downmix = true
        let inputProvider = AudioInputProvider(buffer: input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            inputProvider.next(inputStatus)
        }
        if let conversionError { throw conversionError }
        guard status != .error else {
            throw EngineError.loadFailed("Could not convert audio file")
        }
        guard let channels = output.floatChannelData else {
            throw EngineError.loadFailed("Audio converter did not produce Float32 samples")
        }
        return Array(UnsafeBufferPointer(start: channels[0], count: Int(output.frameLength)))
    }
}
