import Foundation

/// history.log: one `YYYY-MM-DD HH:MM:SS<TAB>text` line per result, so text is never lost
/// if a paste misses (port of src/dictation/history.lua).
public enum History {
    public struct Entry: Equatable, Sendable {
        public let time: String
        public let text: String
    }

    static let tailBytes = 64 * 1024 // enough for hundreds of entries

    public static func format(_ text: String, at date: Date) -> String {
        let flat = text.replacingOccurrences(of: "[\r\n]+", with: " ", options: .regularExpression)
        return "\(stamp(date))\t\(flat)\n"
    }

    public static func append(_ text: String, to file: URL, at date: Date) throws {
        if !FileManager.default.fileExists(atPath: file.path) {
            try Data().write(to: file)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(format(text, at: date).utf8))
    }

    /// Newest `count` entries first; reads only the end of the file.
    public static func recent(_ file: URL, count: Int) -> [Entry] {
        guard count > 0, let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let from = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: from)
        var data = (try? handle.readToEnd()) ?? Data()
        if from > 0, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = data[(newline + 1)...] // drop the partial first line
        }
        let entries = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap(entry)
        return Array(entries.suffix(count).reversed())
    }

    public static func label(_ entry: Entry, today: String, maxChars: Int) -> String {
        let time = Array(entry.time)
        let date = String(time[0..<10])
        let hm = String(time[11..<16])
        let when = date == today ? hm : "\(String(time[8..<10])).\(String(time[5..<7])) \(hm)"
        var text = entry.text
        if text.count > maxChars {
            text = String(text.prefix(maxChars - 1)).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) + "…"
        }
        return "\(when) · \(text)"
    }

    /// Drops entries older than `cutoff` and malformed lines; rewrites via temp + rename.
    /// Returns the number of removed lines.
    @discardableResult
    public static func prune(_ file: URL, before cutoff: Date) -> Int {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return 0 }
        var kept: [Substring] = []
        var removed = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast(text.hasSuffix("\n") ? 1 : 0) {
            if let time = parse(String(line.prefix(19))), time >= cutoff, line.dropFirst(19).first == "\t" {
                kept.append(line)
            } else {
                removed += 1
            }
        }
        guard removed > 0 else { return 0 }
        let output = kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n"
        let temporary = file.appendingPathExtension("tmp")
        guard (try? output.write(to: temporary, atomically: false, encoding: .utf8)) != nil,
              rename(temporary.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            return 0
        }
        return removed
    }

    public static func clear(_ file: URL) throws {
        try Data().write(to: file)
    }

    static func parse(_ stamp: String) -> Date? {
        formatter.date(from: stamp)
    }

    public static func stamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static func entry(_ line: Substring) -> Entry? {
        guard line.count > 20, line.dropFirst(19).first == "\t", parse(String(line.prefix(19))) != nil else { return nil }
        let text = String(line.dropFirst(20))
        return text == "(history started)" ? nil : Entry(time: String(line.prefix(19)), text: text)
    }

    // Local time, like os.date in the Lua tool.
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

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
        let name = History.stamp(now).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "-")
        let file = dir.appending(path: "\(name).wav")
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
