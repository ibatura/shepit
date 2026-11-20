import Foundation

/// One stream's capture (the call tap or the shared microphone), as the session sees it.
public protocol MeetingAudioSource: AnyObject {
    /// Starts delivering blocks with their stream index on any queue. Returns a notice (e.g. microphone fallback).
    @MainActor func start(onSamples: @escaping @Sendable ([Float], Int) -> Void, onFailure: @escaping @MainActor (String) -> Void) throws -> String?
    @MainActor func stop()
}

public protocol VoiceDetector: Sendable {
    /// Speech probability of one frame (`MeetingConfig.frameSamples` samples).
    func probability(_ frame: [Float]) async throws -> Float
}

/// What the session needs from engines; the host adapts ModelHost, Silero and the diarizer.
public struct MeetingServices: Sendable {
    public var makeVAD: @Sendable () throws -> any VoiceDetector
    /// Recognition of one phrase, segments already passed through the dictionary. The second argument is
    /// the stream's `LanguageLeaning` for `TranscriptionRequest.leaning`.
    public var transcribe: @Sendable ([Float], String?) async throws -> Transcript
    /// nil when the speaker model isn't downloaded: labels stay live. Windows only while Remember voices is on.
    public var speakers: (@Sendable ([Float]) async throws -> Diarization)?

    public init(makeVAD: @escaping @Sendable () throws -> any VoiceDetector,
                transcribe: @escaping @Sendable ([Float], String?) async throws -> Transcript,
                speakers: (@Sendable ([Float]) async throws -> Diarization)?) {
        self.makeVAD = makeVAD
        self.transcribe = transcribe
        self.speakers = speakers
    }
}

public struct MeetingConfig: Sendable {
    public var noteFile: URL
    public var frontMatter: String
    public var myName: String
    public var liveLabel = MeetingNote.callLabel
    /// Private dir for call.wav (and mic.wav), deleted when the session ends (spec §5.1).
    public var sessionDir: URL
    /// Where `last-meeting` and `active-meeting` live (spec §5.7, §5.10).
    public var stateDir: URL
    public var engine: EngineChoice
    /// The meeting's name and the app it runs in ("Teams"), when known: shown while it records.
    public var title: String?
    public var app: CallApp?
    public var frameSamples = 4096
    public var threshold: Float = 0.5
    public var maxSilence: TimeInterval = 30 * 60
    public var maxDuration: TimeInterval = 4 * 3600
    public var silentCallAfter: TimeInterval = 120
    /// Mic entries repeating the call within this many seconds are dropped; entries wait this long (MeetingQueue).
    public var echoWindow: TimeInterval = 5
    public var calendar = Calendar.current
    /// Remember voices was on at Start (voices design §4): the microphone is kept in mic.wav too, for samples of your own
    /// lines.
    public var rememberVoices = false
    /// How much of your speech gives your samples: your first lines up to this many seconds, wherever in the meeting.
    public var micVoiceSeconds: Double = 600

    public init(noteFile: URL, frontMatter: String, myName: String, sessionDir: URL, stateDir: URL, engine: EngineChoice) {
        self.noteFile = noteFile
        self.frontMatter = frontMatter
        self.myName = myName
        self.sessionDir = sessionDir
        self.stateDir = stateDir
        self.engine = engine
    }
}

public enum MeetingState: Equatable, Sendable {
    case idle
    case recording(elapsed: TimeInterval, waiting: Int)
    case finishing(left: Int)
    case detectingSpeakers
    case done(speakers: Int?)
    case interrupted

    /// A transcript is recording or still being written.
    public var isActive: Bool {
        switch self {
        case .recording, .finishing, .detectingSpeakers: true
        case .idle, .done, .interrupted: false
        }
    }
}

/// What Start/Stop does at this moment, in the menu and for the meeting hotkey.
public enum MeetingControl: Equatable, Sendable {
    case stop
    /// The transcript is being finished: nothing to start or stop.
    case busy
    /// Start can't run; what is missing.
    case blocked(String)
    case start

    /// `missing`: nil when a meeting can start, else what to download first.
    public init(_ state: MeetingState, missing: String?) {
        switch state {
        case .recording: self = .stop
        case .finishing, .detectingSpeakers: self = .busy
        case .idle, .done, .interrupted: self = missing.map(MeetingControl.blocked) ?? .start
        }
    }
}

/// The statistics row for one meeting (`05-statistics.md` §1). Numbers only.
public struct MeetingRecord: Equatable, Sendable {
    public var start: Date
    public var duration: TimeInterval
    public var wordsMine: Int
    public var wordsCall: Int
    public var speakers: Int?
    public var engine: EngineChoice
    public var diarizationSeconds: Double?
    public var failedChunks: Int
    /// The app the call ran in; nil when Shepit couldn't tie the meeting to one (and for meetings stored before 2026-11-17).
    public var app: CallApp?

    public init(start: Date, duration: TimeInterval, wordsMine: Int, wordsCall: Int, speakers: Int?, engine: EngineChoice,
                diarizationSeconds: Double?, failedChunks: Int, app: CallApp?) {
        self.start = start
        self.duration = duration
        self.wordsMine = wordsMine
        self.wordsCall = wordsCall
        self.speakers = speakers
        self.engine = engine
        self.diarizationSeconds = diarizationSeconds
        self.failedChunks = failedChunks
        self.app = app
    }
}

public struct MeetingError: LocalizedError, Equatable {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

/// One meeting from Start to "Transcript ready" (spec §5.1–5.5, §5.10, §6): two streams → voice detection →
/// phrases → one recognition queue → note in time order; after Stop the queue is drained, remote speakers are
/// detected and relabelled, and the call audio is deleted.
@MainActor
public final class MeetingSession {
    public static let activeMeetingFile = "active-meeting"

    public var onState: ((MeetingState) -> Void)?
    public var onNotice: ((String) -> Void)?
    /// Awaited before Stop returns.
    public var onFinished: ((MeetingRecord) async -> Void)?
    public private(set) var state = MeetingState.idle { didSet { if state != oldValue { onState?(state) } } }
    /// The lines' voice samples by their place in the note, once speakers are detected with windows (voices design §4):
    /// the call's from the call audio, yours from the microphone's.
    public private(set) var samples: [MeetingNote.Place: VoiceSample] = [:]

    public let config: MeetingConfig
    public var title: String? { config.title }
    public var app: CallApp? { config.app }
    private let mic: MeetingAudioSource
    private let call: MeetingAudioSource
    private let services: MeetingServices
    private let now: () -> Date
    private let writer: NoteWriter

    private struct StreamState {
        var cutter: PhraseCutter
        var vad: any VoiceDetector
        var buffer: [Float] = []
        var base = 0 // stream index of buffer[0]
        var nextFrame = 0
        var tail: Task<Void, Never>?
        var closed = false   // no more audio is taken
        var finished = false // its last phrase is queued: it no longer holds entries back
        var lastDelivery = Date.distantPast
        var speech: TimeInterval = 0
    }

    private var streams: [MeetingStream: StreamState] = [:]
    private var queue = MeetingQueue()
    private var transcription: Task<Void, Never>?
    private var callWAV: WAVFileWriter?
    /// The microphone, while Remember voices is on; nil after a write error (no samples of yours).
    private var micWAV: WAVFileWriter?
    /// Seconds of your lines written so far: once they reach `micVoiceSeconds`, the microphone is no longer kept. A line is
    /// written after its audio has come, so the audio of the lines your samples need is in mic.wav by then.
    private var micSpeech = 0.0
    private var capturing = false
    public private(set) var startedAt = Date.distantPast
    private var lastSpeech = Date.distantPast
    private var callHasSound = false
    private var warnedSilentCall = false
    /// Every entry written to the note, with its live label; its stream and offsets for speaker detection.
    private var written: [(entry: MeetingNote.Entry, stream: MeetingStream, offsets: Range<Double>)] = []
    private var words: [MeetingStream: Int] = [.mine: 0, .call: 0]
    private var leanings: [MeetingStream: LanguageLeaning] = [:]
    private var failedChunks = 0
    private var stopping = false
    private var interrupted = false
    private var callAudioBroken = false
    /// A stream that delivers nothing for this long stops holding the other stream's entries back.
    private static let stallAfter: TimeInterval = 10

    public init(config: MeetingConfig, mic: MeetingAudioSource, call: MeetingAudioSource, services: MeetingServices,
                now: @escaping () -> Date = Date.init) {
        self.config = config
        self.mic = mic
        self.call = call
        self.services = services
        self.now = now
        writer = NoteWriter(file: config.noteFile, frontMatter: config.frontMatter)
        queue = MeetingQueue(echoWindow: config.echoWindow)
    }

    // MARK: Start

    /// Creates the note before any capture (a protected folder asks for access here, spec §4.4), then starts both streams.
    public func start() throws {
        do {
            try writer.create()
        } catch {
            throw MeetingError("Can't create the meeting note in \(config.noteFile.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        do {
            for stream in [MeetingStream.mine, .call] {
                streams[stream] = StreamState(cutter: PhraseCutter(frameSamples: config.frameSamples, threshold: config.threshold),
                                              vad: try services.makeVAD())
            }
            try FileManager.default.createDirectory(at: config.sessionDir, withIntermediateDirectories: true)
            callWAV = try WAVFileWriter(file: config.sessionDir.appending(path: "call.wav"))
            if config.rememberVoices { micWAV = try? WAVFileWriter(file: config.sessionDir.appending(path: "mic.wav")) }
            try FileManager.default.createDirectory(at: config.stateDir, withIntermediateDirectories: true)
            try Data((config.noteFile.path + "\n").utf8).write(to: config.stateDir.appending(path: Self.activeMeetingFile), options: .atomic)
            startedAt = now()
            lastSpeech = startedAt
            for stream in [MeetingStream.mine, .call] {
                streams[stream]?.lastDelivery = startedAt
                queue.setFrontier(stream, startedAt) // nothing from either stream may be overtaken before it starts
            }
            capturing = true
            if let notice = try mic.start(onSamples: deliver(.mine), onFailure: { [weak self] in self?.captureFailed(.mine, $0) }) {
                onNotice?(notice)
            }
            do {
                _ = try call.start(onSamples: deliver(.call), onFailure: { [weak self] in self?.captureFailed(.call, $0) })
            } catch {
                mic.stop()
                throw MeetingError("Can't record call audio (\(error.localizedDescription)). Allow Shepit in System Settings → Privacy & Security → Screen & System Audio Recording.")
            }
        } catch {
            capturing = false
            try? FileManager.default.removeItem(at: config.noteFile) // only front matter so far
            callWAV = nil
            micWAV = nil
            streams = [:]
            cleanUpAudio()
            throw error is MeetingError ? error : MeetingError(error.localizedDescription)
        }
        state = .recording(elapsed: 0, waiting: 0)
        if services.speakers == nil {
            onNotice?("Speakers won't be detected: download the speaker model in Settings → Meetings")
        }
    }

    private func deliver(_ stream: MeetingStream) -> @Sendable ([Float], Int) -> Void {
        { [weak self] samples, first in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(stream, samples, first) } }
        }
    }

    // MARK: Dictation (spec §5.8) and a muted call microphone

    /// Why the mic is left out right now; it is skipped while any reason holds.
    private var micSkips: Set<String> = []
    /// Where it was left out, in microphone samples; the last one is open while a reason holds. mic.wav keeps silence
    /// there: what you say while muted or dictating isn't kept for your voice either.
    private var micSkipped: [Range<Int>] = []

    public func dictationStarted(at index: Int) { skipMic("dictation", true, at: index) }
    public func dictationEnded(at index: Int) { skipMic("dictation", false, at: index) }

    /// Muted in the meeting app: what I say then isn't part of the call (Task 11), so it is left out.
    public func micMuted(_ muted: Bool, at index: Int) { skipMic("muted", muted, at: index) }

    private func skipMic(_ reason: String, _ on: Bool, at index: Int) {
        let was = !micSkips.isEmpty
        if on { micSkips.insert(reason) } else { micSkips.remove(reason) }
        if !was, !micSkips.isEmpty {
            streams[.mine]?.cutter.startSkip(at: index)
            micSkipped.append(index..<Int.max)
        }
        if was, micSkips.isEmpty {
            streams[.mine]?.cutter.endSkip(at: index)
            if let open = micSkipped.popLast() { micSkipped.append(open.lowerBound..<max(open.lowerBound, index)) }
        }
    }

    // MARK: Audio → phrases

    private func receive(_ stream: MeetingStream, _ samples: [Float], _ first: Int) {
        guard capturing, let s = streams[stream], !s.closed else { return }
        var block = samples
        let end = s.base + s.buffer.count
        if first > end { block = [Float](repeating: 0, count: first - end) + block } // a gap: keep indexes aligned
        else if first < end { block = Array(block.dropFirst(min(block.count, end - first))) }
        if stream == .call {
            if !callHasSound, block.contains(where: { $0 != 0 }) { callHasSound = true }
            if !callAudioBroken {
                do {
                    try callWAV?.append(block)
                } catch {
                    // Later offsets would no longer match the note: no speaker detection for this meeting.
                    callAudioBroken = true
                    onNotice?("Can't keep call audio, speakers won't be detected: \(error.localizedDescription)")
                }
            }
        } else if let micWAV, micSpeech < config.micVoiceSeconds {
            var kept = block
            for skipped in micSkipped {
                let silent = skipped.clamped(to: end..<end + block.count) // empty when it isn't in this block
                kept.replaceSubrange((silent.lowerBound - end)..<(silent.upperBound - end), with: repeatElement(0, count: silent.count))
            }
            do {
                try micWAV.append(kept)
            } catch {
                self.micWAV = nil // later offsets would no longer match your lines
            }
        }
        // Mutated in place: copying the state out would copy the whole buffer on every block.
        streams[stream]!.buffer += block
        streams[stream]!.lastDelivery = now()
        while let current = streams[stream], current.base + current.buffer.count - current.nextFrame >= config.frameSamples {
            let offset = current.nextFrame - current.base
            let frame = Array(current.buffer[offset..<(offset + config.frameSamples)])
            let frameStart = current.nextFrame
            let vad = current.vad
            let previous = current.tail
            streams[stream]!.nextFrame += config.frameSamples
            streams[stream]!.tail = Task { [weak self] in
                await previous?.value
                let probability = (try? await vad.probability(frame)) ?? 0
                self?.voice(stream, probability, frameStart)
            }
        }
    }

    private func voice(_ stream: MeetingStream, _ probability: Float, _ frameStart: Int) {
        guard !interrupted, streams[stream] != nil else { return }
        if probability >= config.threshold { lastSpeech = now() }
        let phrases = streams[stream]!.cutter.push(probability: probability, frameStart: frameStart)
        enqueue(stream, phrases)
    }

    private func enqueue(_ stream: MeetingStream, _ phrases: [Phrase]) {
        guard let s = streams[stream] else { return }
        for phrase in phrases {
            let from = max(0, phrase.start - s.base), to = min(s.buffer.count, phrase.end - s.base)
            guard from < to else { continue }
            queue.add(MeetingChunk(stream: stream, start: phrase.start, end: phrase.end, wallStart: wall(phrase.start),
                                   samples: Array(s.buffer[from..<to])))
            if stream == .mine { streams[stream]!.speech += Double(phrase.end - phrase.start) / 16_000 }
        }
        // Audio before the frontier can't be in a future phrase.
        let keepFrom = min(s.cutter.frontier, s.nextFrame)
        if keepFrom - s.base > 16_000 {
            streams[stream]!.buffer.removeFirst(keepFrom - s.base)
            streams[stream]!.base = keepFrom
        }
        updateFrontier(stream)
        flush()
        pump()
    }

    private func updateFrontier(_ stream: MeetingStream) {
        guard let s = streams[stream] else { return }
        queue.setFrontier(stream, s.finished ? nil : wall(s.cutter.frontier))
    }

    private func wall(_ index: Int) -> Date {
        startedAt.addingTimeInterval(Double(index) / 16_000)
    }

    // MARK: Recognition and the note

    private func pump() {
        guard !interrupted, transcription == nil, let chunk = queue.next() else { return }
        let transcribe = services.transcribe
        let leaning = leanings[chunk.stream]?.leaning
        transcription = Task { [weak self] in
            var transcript: Transcript?
            for _ in 0..<2 where transcript == nil { transcript = try? await transcribe(chunk.samples, leaning) } // one retry
            self?.recognized(chunk, transcript)
        }
        publishState()
    }

    private func recognized(_ chunk: MeetingChunk, _ transcript: Transcript?) {
        transcription = nil
        guard !interrupted else { return }
        if let transcript {
            let start = Double(chunk.start) / 16_000
            let duration = Double(chunk.end - chunk.start) / 16_000
            leanings[chunk.stream, default: LanguageLeaning()].add(seconds: duration, detected: transcript.detectedLanguage)
            var segments = transcript.segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if segments.isEmpty, !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments = [Segment(text: transcript.text, start: 0, end: duration)]
            }
            queue.done(chunk.id, entries: segments.map { segment in
                MeetingEntry(stream: chunk.stream, wallStart: chunk.wallStart.addingTimeInterval(segment.start),
                             offsets: (start + segment.start)..<(start + max(segment.end, segment.start + 0.01)), text: segment.text)
            })
        } else {
            failedChunks += 1
            queue.failed(chunk.id)
        }
        flush()
        pump()
        publishState()
    }

    private func flush() {
        guard !interrupted else { return }
        write(queue.ready())
    }

    private func write(_ entries: [MeetingEntry]) {
        for entry in entries {
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.contains(where: { $0.isLetter || $0.isNumber }), !MeetingNote.isFiller(text) else { continue }
            let label = entry.stream == .mine ? config.myName : config.liveLabel
            do {
                try writer.append(MeetingNote.entry(label: label, at: entry.wallStart, text: text, calendar: config.calendar))
            } catch {
                onNotice?("Can't write the meeting note \(config.noteFile.path): \(error.localizedDescription)")
                continue
            }
            let timestamp = MeetingNote.timestamp(entry.wallStart, calendar: config.calendar)
            written.append((MeetingNote.Entry(label: label, timestamp: timestamp, text: text, line: written.count), entry.stream, entry.offsets))
            if entry.stream == .mine { micSpeech += entry.offsets.upperBound - entry.offsets.lowerBound }
            if !entry.failed { words[entry.stream, default: 0] += text.split(whereSeparator: \.isWhitespace).count }
        }
    }

    private func publishState() {
        switch state {
        case .recording: state = .recording(elapsed: now().timeIntervalSince(startedAt), waiting: queue.waiting)
        case .finishing: state = .finishing(left: queue.waiting)
        default: break
        }
    }

    // MARK: Failures, limits

    private func captureFailed(_ stream: MeetingStream, _ message: String) {
        guard capturing, streams[stream]?.closed == false else { return }
        try? writer.append(MeetingNote.stoppedLine(stream, at: now(), calendar: config.calendar))
        onNotice?(message)
        Task { await self.finishStream(stream) }
    }

    /// No more audio from `stream`: its open phrase becomes a last chunk and it stops holding entries back.
    /// Safe to run twice (from a capture failure and from stop): whichever gets there first queues the phrase.
    private func finishStream(_ stream: MeetingStream) async {
        guard streams[stream] != nil else { return }
        streams[stream]!.closed = true
        await streams[stream]?.tail?.value
        guard !interrupted, let s = streams[stream], !s.finished else { return }
        let last = streams[stream]!.cutter.finish()
        streams[stream]!.finished = true
        enqueue(stream, last)
        if capturing, !stopping, streams.values.allSatisfy(\.finished) {
            onNotice?("Meeting transcript stopped: no audio left to record")
            await stop()
        }
    }

    /// Called by the host every second: elapsed time, auto-stop (spec §5.10), the silent-call notice (§6).
    public func tick() {
        guard capturing, !stopping else { return }
        let time = now()
        publishState()
        // A capture that went quiet without an error must not hold the other stream's entries in memory.
        for (stream, s) in streams where !s.finished && time.timeIntervalSince(s.lastDelivery) > Self.stallAfter {
            let behind = max(wall(s.cutter.frontier), time.addingTimeInterval(-Self.stallAfter))
            queue.setFrontier(stream, behind)
        }
        flush()
        if time.timeIntervalSince(startedAt) >= config.maxDuration {
            onNotice?("Meeting transcript stopped after \(Int(config.maxDuration / 3600)) hours")
            Task { await stop() }
        } else if time.timeIntervalSince(lastSpeech) >= config.maxSilence {
            onNotice?("Meeting transcript stopped: no speech for \(Int(config.maxSilence / 60)) minutes")
            Task { await stop() }
        } else if !warnedSilentCall, !callHasSound, (streams[.mine]?.speech ?? 0) > config.silentCallAfter {
            warnedSilentCall = true
            onNotice?("Call audio may not be recorded: check System Settings → Privacy & Security → Screen & System Audio Recording → Shepit")
        }
    }

    // MARK: Stop

    /// Stops capture, writes what's left, detects speakers, deletes the audio (spec §5.5).
    public func stop() async {
        guard capturing, !stopping else { return }
        stopping = true
        mic.stop()
        call.stop()
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } } // blocks already queued
        guard !interrupted else { return }
        capturing = false
        state = .finishing(left: queue.waiting)
        for stream in [MeetingStream.mine, .call] { await finishStream(stream) }
        while let running = transcription {
            await running.value
            guard !interrupted else { return }
            state = .finishing(left: queue.waiting)
        }
        guard !interrupted else { return }
        flush()

        var speakers: Int?
        var diarizationSeconds: Double?
        do { try callWAV?.finish() } catch {}
        callWAV = nil
        if let detect = services.speakers, !callAudioBroken, written.contains(where: { $0.stream == .call }) {
            state = .detectingSpeakers
            do {
                let samples = try WAV.read(config.sessionDir.appending(path: "call.wav"))
                let began = Date()
                let diarization = try await detect(samples)
                guard !interrupted else { return }
                diarizationSeconds = Date().timeIntervalSince(began)
                speakers = try relabel(diarization.turns)
                self.samples = lineSamples(of: .call) { Voices.lineSamples($0, diarization) }
            } catch {
                onNotice?("Speakers not detected: \(error.localizedDescription)")
            }
        }
        let micKept = micWAV?.samples ?? 0
        let micWhole = micWAV.map { (try? $0.finish()) != nil } ?? false
        micWAV = nil
        if let detect = services.speakers, micWhole, written.contains(where: { $0.stream == .mine }) {
            state = .detectingSpeakers
            // Only your lines' audio is detected, up to micVoiceSeconds of it. Without your voice from the microphone the
            // transcript is still whole: nothing to say.
            let speech = Voices.speech(of: written.filter { $0.stream == .mine }.map(\.offsets), upTo: config.micVoiceSeconds, within: micKept)
            if let diarization = try? await detect(try WAV.read(config.sessionDir.appending(path: "mic.wav"), speech.ranges)) {
                guard !interrupted else { return }
                // The samples of the lines `speech` took, your first ones.
                samples.merge(lineSamples(of: .mine) { _ in Voices.yourSamples(speech.lines, diarization) }) { call, _ in call }
            }
        }
        cleanUpAudio()
        let record = MeetingRecord(start: startedAt, duration: now().timeIntervalSince(startedAt), wordsMine: words[.mine] ?? 0,
                                   wordsCall: words[.call] ?? 0, speakers: speakers, engine: config.engine,
                                   diarizationSeconds: diarizationSeconds, failedChunks: failedChunks, app: config.app)
        state = .done(speakers: speakers)
        await onFinished?(record)
    }

    /// Person N labels into the note; returns how many remote speakers were found.
    private func relabel(_ turns: [SpeakerTurn]) throws -> Int {
        let callEntries = written.filter { $0.stream == .call }
        let labels = Speakers.assign(callEntries.map(\.offsets), turns: turns)
        var next = labels.makeIterator()
        let entries = written.map { (timestamp: $0.entry.timestamp, label: $0.stream == .call ? next.next() ?? nil : nil) }
        guard FileManager.default.fileExists(atPath: config.noteFile.path) else { return Set(labels.compactMap { $0 }).count }
        let note = try String(contentsOf: config.noteFile, encoding: .utf8)
        let relabelled = Speakers.relabel(note, live: config.liveLabel, entries: entries)
        if relabelled != note { try Data(relabelled.utf8).write(to: config.noteFile, options: .atomic) }
        return Set(labels.compactMap { $0 }).count
    }

    /// The samples `sample` gives the lines of `stream` (offsets in seconds), by their place in the note; fewer samples
    /// than lines are the first lines'.
    private func lineSamples(of stream: MeetingStream, _ sample: ([Range<Double>]) -> [VoiceSample?]) -> [MeetingNote.Place: VoiceSample] {
        let lines = zip(written, places).filter { $0.0.stream == stream }
        return Dictionary(uniqueKeysWithValues: zip(lines.map(\.1), sample(lines.map(\.0.offsets))).compactMap { place, sample in
            sample.map { (place, $0) }
        })
    }

    /// Each entry's place in the note, as `MeetingStore` pairs them.
    private var places: [MeetingNote.Place] { MeetingNote.places(written.map(\.entry.timestamp)) }

    /// Each entry's talk time in seconds, by its place in the note.
    public var talk: [MeetingNote.Place: Double] {
        Dictionary(uniqueKeysWithValues: zip(places, written.map { $0.offsets.upperBound - $0.offsets.lowerBound }))
    }

    /// Entries written to the note so far.
    public var entries: Int { written.count }

    /// The entries written so far with their live labels, for the window (Meetings design §7); `line` is the entry's index.
    public var liveEntries: [MeetingNote.Entry] { written.map(\.entry) }

    /// Words recognized so far on both sides.
    public var wordCount: Int { words.values.reduce(0, +) }

    /// A finished transcript without a single entry: deletes the note (call offer design §5.4).
    /// False, and nothing changes, when there are entries or the session is not done.
    @discardableResult public func removeEmptyNote() -> Bool {
        guard case .done = state, written.isEmpty else { return false }
        try? FileManager.default.removeItem(at: config.noteFile)
        return true
    }

    /// Quit or logout mid-session: keep what's written, mark it, delete the audio (spec §5.10). No resume.
    public func interrupt() {
        guard capturing || stopping, !interrupted else { return }
        if case .done = state { return }
        if capturing {
            mic.stop()
            call.stop()
        }
        capturing = false
        // Every recognized entry, even one still waiting for the other stream, is written before the marker.
        write(queue.releaseAll())
        interrupted = true
        transcription?.cancel()
        try? writer.append(MeetingNote.interruptedLine(at: now(), calendar: config.calendar))
        try? callWAV?.finish()
        callWAV = nil
        try? micWAV?.finish()
        micWAV = nil
        cleanUpAudio()
        state = .interrupted
    }

    private func cleanUpAudio() {
        try? FileManager.default.removeItem(at: config.sessionDir)
        try? FileManager.default.removeItem(at: config.stateDir.appending(path: Self.activeMeetingFile))
    }

    // MARK: Launch recovery

    /// At launch: delete leftover session dirs (`meeting-*` in `sessionsRoot`) and, after a crash, mark the
    /// note that was being written as interrupted. Returns that note if it was marked.
    @discardableResult
    public static func recover(stateDir: URL, sessionsRoot: URL, now: Date, calendar: Calendar = .current) -> URL? {
        let fm = FileManager.default
        for dir in (try? fm.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: nil)) ?? []
        where dir.lastPathComponent.hasPrefix("meeting-") {
            try? fm.removeItem(at: dir)
        }
        // Earlier versions kept the newest note's path here; the meetings database knows it now.
        try? fm.removeItem(at: stateDir.appending(path: "last-meeting"))
        let active = stateDir.appending(path: activeMeetingFile)
        guard let path = try? String(contentsOf: active, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        try? fm.removeItem(at: active)
        let note = URL(fileURLWithPath: path)
        guard !path.isEmpty, fm.fileExists(atPath: note.path) else { return nil }
        try? NoteWriter(file: note, frontMatter: "").append(MeetingNote.interruptedLine(at: now, calendar: calendar))
        return note
    }

    /// Waits until queued audio, voice detection and recognition have settled (for tests).
    public func settle() async {
        for _ in 0..<50 {
            await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
            for stream in [MeetingStream.mine, .call] { await streams[stream]?.tail?.value }
            if let running = transcription { await running.value } else { return }
        }
    }
}
