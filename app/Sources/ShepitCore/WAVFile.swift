import Foundation

/// A 16 kHz mono 16-bit WAV written as audio arrives (the meeting's call.wav, spec §5.1);
/// `finish` fills in the sizes in the header.
public final class WAVFileWriter: @unchecked Sendable {
    public let file: URL
    private let handle: FileHandle
    private var dataBytes: UInt32 = 0

    public init(file: URL) throws {
        self.file = file
        try WAV.data(samples: []).write(to: file)
        handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
    }

    public func append(_ samples: [Float]) throws {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            withUnsafeBytes(of: Int16((max(-1, min(1, sample)) * 32_767).rounded()).littleEndian) { data.append(contentsOf: $0) }
        }
        try handle.write(contentsOf: data)
        dataBytes += UInt32(data.count)
    }

    public func finish() throws {
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: withUnsafeBytes(of: (36 + dataBytes).littleEndian) { Data($0) })
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: withUnsafeBytes(of: dataBytes.littleEndian) { Data($0) })
        try handle.close()
    }
}

extension WAV {
    /// Samples of a WAV this app wrote (16-bit PCM, 44-byte header).
    public static func read(_ file: URL) throws -> [Float] {
        let data = try Data(contentsOf: file, options: .mappedIfSafe) // an hour of call audio is ~115 MB
        guard data.count >= 44, data.prefix(4) == Data("RIFF".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        return data.dropFirst(44).withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32_767 }
        }
    }
}
