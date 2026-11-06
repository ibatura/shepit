import Foundation

public enum MeetingStream: String, Sendable {
    case mine // microphone
    case call // system audio
}

/// A phrase waiting for recognition: sample offsets in its stream, wall-clock start, and its audio.
public struct MeetingChunk: Sendable, Identifiable {
    public let id = UUID()
    public var stream: MeetingStream
    public var start: Int
    public var end: Int
    public var wallStart: Date
    public var samples: [Float]

    public init(stream: MeetingStream, start: Int, end: Int, wallStart: Date, samples: [Float]) {
        self.stream = stream
        self.start = start
        self.end = end
        self.wallStart = wallStart
        self.samples = samples
    }
}

/// One line of the note: who, when, where in the stream (seconds, for speaker mapping), what.
public struct MeetingEntry: Equatable, Sendable {
    public var stream: MeetingStream
    public var wallStart: Date
    public var offsets: Range<Double>
    public var text: String
    public var failed: Bool

    public init(stream: MeetingStream, wallStart: Date, offsets: Range<Double>, text: String, failed: Bool = false) {
        self.stream = stream
        self.wallStart = wallStart
        self.offsets = offsets
        self.text = text
        self.failed = failed
    }
}

/// Recognition queue for both streams and the chronological-flush rule (spec §5.3, §5.4): chunks go out
/// oldest first, one at a time; an entry is released only when no stream can still produce an earlier one.
///
/// Echo: on speakers the microphone hears the call, and the same phrase came out twice, once under my name
/// (Task 11, Test4). An entry is held until nothing can still start within `echoWindow` after it, and a mic
/// entry whose words were said on the call within `echoWindow` is dropped.
public struct MeetingQueue: Sendable {
    public static let failedText = "⚠ не вдалося розпізнати"

    public let echoWindow: TimeInterval
    /// Call entries already released, for echoes released later (last minute only).
    private var recentCall: [MeetingEntry] = []

    private var queued: [MeetingChunk] = []
    private var inFlight: MeetingChunk?
    private var finished: [(entry: MeetingEntry, order: Int)] = []
    private var order = 0
    /// Per stream: the earliest wall time of audio not yet in a chunk (an open phrase, or the VAD position
    /// minus padding). nil = the stream can't produce anything new (stopped, or not set).
    private var frontiers: [MeetingStream: Date] = [:]

    public init(echoWindow: TimeInterval = 0) {
        self.echoWindow = echoWindow
    }

    /// Chunks queued or being recognized.
    public var waiting: Int { queued.count + (inFlight == nil ? 0 : 1) }

    public mutating func add(_ chunk: MeetingChunk) {
        queued.append(chunk)
    }

    /// The oldest queued chunk, or nil while one is in flight.
    public mutating func next() -> MeetingChunk? {
        guard inFlight == nil, let index = queued.indices.min(by: { queued[$0].wallStart < queued[$1].wallStart }) else { return nil }
        inFlight = queued.remove(at: index)
        return inFlight
    }

    public mutating func done(_ id: MeetingChunk.ID, entries: [MeetingEntry]) {
        guard inFlight?.id == id else { return }
        inFlight = nil
        for entry in entries {
            finished.append((entry, order))
            order += 1
        }
    }

    public mutating func failed(_ id: MeetingChunk.ID) {
        guard let chunk = inFlight, chunk.id == id else { return }
        let offsets = Double(chunk.start) / 16_000..<Double(chunk.end) / 16_000
        done(id, entries: [MeetingEntry(stream: chunk.stream, wallStart: chunk.wallStart, offsets: offsets, text: Self.failedText, failed: true)])
    }

    public mutating func setFrontier(_ stream: MeetingStream, _ date: Date?) {
        frontiers[stream] = date
    }

    /// Every recognized entry in time order, whatever is still pending (the session is being interrupted).
    public mutating func releaseAll() -> [MeetingEntry] {
        let all = finished.sorted { ($0.entry.wallStart, $0.order) < ($1.entry.wallStart, $1.order) }.map(\.entry)
        finished = []
        return dropEchoes(all, unreleased: [])
    }

    /// Entries safe to write now, in time order; they are removed from the queue.
    public mutating func ready() -> [MeetingEntry] {
        let pending = queued.map(\.wallStart) + [inFlight?.wallStart].compactMap { $0 } + Array(frontiers.values)
        let limit = pending.min() ?? .distantFuture
        let sorted = finished.sorted { ($0.entry.wallStart, $0.order) < ($1.entry.wallStart, $1.order) }
        let release = sorted.prefix { $0.entry.wallStart.addingTimeInterval(echoWindow) <= limit }
        finished = Array(sorted.dropFirst(release.count))
        return dropEchoes(release.map(\.entry), unreleased: finished.map(\.entry))
    }

    private mutating func dropEchoes(_ entries: [MeetingEntry], unreleased: [MeetingEntry]) -> [MeetingEntry] {
        let calls = recentCall + (entries + unreleased).filter { $0.stream == .call && !$0.failed }
        let kept = entries.filter { entry in
            guard entry.stream == .mine, !entry.failed else { return true }
            let from = entry.wallStart.addingTimeInterval(-echoWindow)
            let to = Self.end(entry).addingTimeInterval(echoWindow)
            let heard = Set(calls.filter { Self.end($0) >= from && $0.wallStart <= to }.flatMap { Self.words($0.text) })
            return !Self.isEcho(Self.words(entry.text), heard: heard)
        }
        recentCall += entries.filter { $0.stream == .call && !$0.failed }
        if let last = entries.last?.wallStart { recentCall.removeAll { Self.end($0) < last.addingTimeInterval(-60) } }
        return kept
    }

    /// Most of the words were just said on the call: 70% of them, or all for one or two words. Checked on
    /// Test4 (17 of 19 echoes dropped) and the Teams call on headphones (none of my 17 phrases dropped).
    static func isEcho(_ words: [String], heard: Set<String>) -> Bool {
        guard !words.isEmpty else { return false }
        let found = words.filter { word in heard.contains(word) || word.count >= 4 && heard.contains { close(word, $0) } }.count
        return words.count <= 2 ? found == words.count : Double(found) >= Double(words.count) * 0.7
    }

    /// One letter apart (an edit, insert or delete): the mic hears the call less clearly ("Veles" / "Velas").
    static func close(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        guard abs(x.count - y.count) <= 1, min(x.count, y.count) >= 3 else { return false }
        var i = 0, j = 0, edits = 0
        while i < x.count, j < y.count {
            if x[i] == y[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if x.count > y.count { i += 1 } else if y.count > x.count { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (x.count - i) + (y.count - j) <= 1
    }

    /// Words of three letters or more: short ones ("і", "так", "we") are said on both sides all the time.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init).filter { $0.count >= 3 }
    }

    private static func end(_ entry: MeetingEntry) -> Date {
        entry.wallStart.addingTimeInterval(entry.offsets.upperBound - entry.offsets.lowerBound)
    }
}
