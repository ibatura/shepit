import Foundation

/// 16 kHz mono 16-bit PCM WAV, for failed audio.
public enum WAV {
    public static let sampleRate = 16_000

    public static func data(samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let dataBytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + dataBytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(dataBytes)
        for sample in samples {
            append(Int16((max(-1, min(1, sample)) * 32_767).rounded()))
        }
        return data
    }
}

/// Audio of failed attempts, kept for `failedAudioHours` (port of platform.lua keepFailed / cleanupFailed).
public enum FailedAudio {
    /// Writes the samples as `<date>.wav` in `dir` and removes old files. `hours == 0` keeps nothing.
    public static func keep(_ samples: [Float], in dir: URL, hours: Int, now: Date) throws -> URL? {
        guard hours > 0 else { return nil }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "\(DateFormatter.english("yyyy-MM-dd_HH-mm-ss", .current).string(from: now)).wav")
        // .atomic writes a temp file and renames it, so a symlink at `file` is replaced, not written through.
        try WAV.data(samples: samples).write(to: file, options: .atomic)
        cleanup(dir, olderThanHours: hours, now: now)
        return file
    }

    public static func cleanup(_ dir: URL, olderThanHours hours: Int, now: Date) {
        let cutoff = now.addingTimeInterval(-Double(hours) * 3600)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "wav" {
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
