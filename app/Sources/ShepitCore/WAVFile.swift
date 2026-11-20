import Foundation

/// A 16 kHz mono 16-bit WAV written as audio arrives (the meeting's call.wav, spec §5.1);
/// `finish` fills in the sizes in the header.
public final class WAVFileWriter: @unchecked Sendable {
    public let file: URL
    private let handle: FileHandle
    private var dataBytes: UInt32 = 0
    /// Samples written so far.
    public var samples: Int { Int(dataBytes) / 2 }

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
    public static func read(_ file: URL) throws -> [Float] { try read(file, [0..<Int.max]) }

    /// The samples of `parts` (sample indexes) of a WAV this app wrote, one after another; what lies past its end is left
    /// out. The file is mapped, so only those parts are read: an hour of call audio is ~115 MB.
    public static func read(_ file: URL, _ parts: [Range<Int>]) throws -> [Float] {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count >= 44, data.prefix(4) == Data("RIFF".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        return data.dropFirst(44).withUnsafeBytes { raw in
            let all = raw.bindMemory(to: Int16.self)
            let kept = parts.map { $0.clamped(to: 0..<all.count) }
            var samples: [Float] = []
            samples.reserveCapacity(kept.reduce(0) { $0 + $1.count }) // one copy of a whole call, not two
            for part in kept { samples += all[part].lazy.map { Float(Int16(littleEndian: $0)) / 32_767 } }
            return samples
        }
    }
}
