@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import ShepitCore

enum CallTapError: Error, CustomStringConvertible {
    case coreAudio(String, OSStatus)
    case format(String)

    var description: String {
        switch self {
        case let .coreAudio(step, status): "\(step) failed (OSStatus \(status))"
        case let .format(message): message
        }
    }
}

/// System audio (everything playing on the Mac except Shepit itself) as 16 kHz mono Float32,
/// through a Core Audio process tap in a private tap-only aggregate device (spec §4.1).
///
/// When the default output device changes (headphones ↔ speakers, Bluetooth gone) the tap's format can
/// change, so the tap is rebuilt and the stream continues: sample indexes keep counting from where they were.
/// `start`/`stop` and restarts run on the main queue — never on the audio queue, where `AudioDeviceStop`
/// would wait for itself.
///
/// The stream index is real time since `start`: macOS doesn't run the tap while nothing plays, and a restart
/// loses a moment, so gaps are filled with silence from the system clock (by each block's host time, and by
/// a timer while no blocks come). That keeps note times right and lets the other stream's entries through.
final class CallTap: @unchecked Sendable {
    /// Called on the tap's queue with each converted block and the stream index of its first sample.
    var onSamples: (@Sendable (_ samples: [Float], _ firstIndex: Int) -> Void)?
    /// Called on the main queue when the tap could not be rebuilt; the stream has stopped.
    var onFailure: (@MainActor (String) -> Void)?
    private(set) var restarts = 0
    private(set) var tapRate: Double = 0
    private(set) var deviceRate: Double = 0
    /// Diagnostics for `tap-test`.
    private(set) var callbacks = 0
    private(set) var lastProblem = ""

    private let queue = DispatchQueue(label: "dev.shepit.calltap")
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?
    private let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var nextIndex = 0 // touched on the audio queue only (reset before the first IOProc runs)
    private var startNanos: UInt64 = 0
    private var filler: DispatchSourceTimer?
    /// Seconds of silence added for gaps (diagnostics).
    private(set) var filledSeconds = 0.0
    /// Blocks arrive this late at most; the timer fills only behind it.
    private static let latency = 0.5
    private var running = false
    private var pendingRestart: DispatchWorkItem?
    private var outputListener: AudioObjectPropertyListenerBlock?

    @MainActor
    func start() throws {
        nextIndex = 0
        filledSeconds = 0
        restarts = 0
        startNanos = AudioConvertHostTimeToNanos(AudioGetCurrentHostTime())
        try open()
        running = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { @Sendable [weak self] in // runs on the audio queue, not the main actor
            guard let self else { return }
            fill(to: elapsed(AudioGetCurrentHostTime()) - Self.latency)
        }
        timer.resume()
        filler = timer
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRestart() }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        outputListener = listener
    }

    @MainActor
    func stop() {
        running = false
        filler?.cancel()
        filler = nil
        pendingRestart?.cancel()
        pendingRestart = nil
        if let outputListener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputListener)
        }
        outputListener = nil
        close()
        // A filler run or block already queued finishes here, so nothing is delivered after stop returns.
        queue.sync {}
    }

    /// Debounced: a Bluetooth switch fires several changes within a moment.
    private func scheduleRestart() {
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.restart() } }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Rebuilds the tap; a Bluetooth device that just went away can make it fail for a moment, so it retries.
    @MainActor
    private func restart(attempt: Int = 1) {
        guard running else { return }
        close()
        do {
            try open()
            restarts += 1
        } catch where attempt < 3 {
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.restart(attempt: attempt + 1) } }
            pendingRestart = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        } catch {
            stop()
            onFailure?("call audio stopped: \(error)")
        }
    }

    private func open() throws {
        do {
            try build()
        } catch {
            close()
            throw error
        }
    }

    private func build() throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: Self.ownProcessObject().map { [$0] } ?? [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(description, &tapID))

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = Self.address(kAudioTapPropertyFormat)
        try check("read tap format", AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format))
        tapRate = format.mSampleRate

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Shepit call audio",
            kAudioAggregateDeviceUIDKey: "dev.shepit.calltap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        try check("AudioHardwareCreateAggregateDevice", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))

        // The aggregate's rate, not the tap's, is the rate the samples arrive at (§4.1 sample-rate trap).
        var rate = Float64(0)
        size = UInt32(MemoryLayout<Float64>.size)
        address = Self.address(kAudioDevicePropertyNominalSampleRate)
        try check("read device rate", AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, &rate))
        deviceRate = rate
        format.mSampleRate = rate
        guard let input = AVAudioFormat(streamDescription: &format),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw CallTapError.format("unsupported tap format \(format)")
        }
        self.converter = converter

        try check("AudioDeviceCreateIOProcIDWithBlock", AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
            [weak self] _, inputData, inputTime, _, _ in
            guard let self else { return }
            if inputTime.pointee.mFlags.contains(.hostTimeValid) {
                let at = elapsed(inputTime.pointee.mHostTime)
                fill(to: at)
                // The timer already filled past this block (the queue stalled): drop it rather than run ahead of real time.
                guard Int(at * 16_000) >= nextIndex - 1_600 else { return }
            }
            convert(inputData, format: input)
        })
        try check("AudioDeviceStart", AudioDeviceStart(aggregateID, procID))
    }

    private func close() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        converter = nil
    }

    private func convert(_ data: UnsafePointer<AudioBufferList>, format: AVAudioFormat) {
        callbacks += 1
        guard let converter,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: data, deallocator: nil),
              buffer.frameLength > 0 else {
            lastProblem = "no input buffer: \(data.pointee.mNumberBuffers) buffers, \(data.pointee.mBuffers.mDataByteSize) bytes, format \(format)"
            return
        }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * output.sampleRate / format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var fed = false // convert(to:) calls the block synchronously
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData else {
            lastProblem = "convert: \(String(describing: error)), out \(out.frameLength), in \(buffer.frameLength)"
            return
        }
        let first = nextIndex
        nextIndex += Int(out.frameLength)
        onSamples?(Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength))), first)
    }

    private func elapsed(_ hostTime: UInt64) -> Double {
        Double(Int64(AudioConvertHostTimeToNanos(hostTime)) - Int64(startNanos)) / 1e9
    }

    /// On the audio queue: silence up to `seconds` into the stream, if more than 0.1 s is missing.
    private func fill(to seconds: Double) {
        let target = Int(seconds * 16_000)
        guard target - nextIndex > 1_600 else { return }
        filledSeconds += Double(target - nextIndex) / 16_000
        while nextIndex < target {
            let count = min(16_000, target - nextIndex)
            let first = nextIndex
            nextIndex += count
            onSamples?([Float](repeating: 0, count: count), first)
        }
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else {
            close()
            throw CallTapError.coreAudio(step, status)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Shepit's own Core Audio process object, so its sounds stay out of the tap.
    private static func ownProcessObject() -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }
}

/// `Shepit tap-test <seconds> <out.wav>` — records system audio to a WAV and writes `<out.wav>.log`.
/// Run it through `open -n -a Shepit.app --args tap-test …` so macOS asks for the permission in Shepit's name.
enum TapTest {
    @MainActor
    static func run(arguments: [String]) async -> Int32 {
        guard arguments.count == 2, let seconds = Double(arguments[0]) else {
            print("usage: Shepit tap-test <seconds> <out.wav>")
            return 2
        }
        let out = URL(fileURLWithPath: arguments[1])
        let collected = Collected()
        let tap = CallTap()
        tap.onSamples = { samples, _ in collected.append(samples) }
        var log = "started: \(Date())\n"
        do {
            try tap.start()
            try await Task.sleep(for: .seconds(seconds))
            tap.stop()
        } catch {
            log += "error: \(error)\n"
        }
        let samples = collected.samples
        let nonZero = samples.lazy.filter { $0 != 0 }.count
        log += "callbacks: \(tap.callbacks)\nrestarts: \(tap.restarts)\nproblem: \(tap.lastProblem)\n"
        log += "tap rate: \(tap.tapRate)\ndevice rate: \(tap.deviceRate)\nsamples: \(samples.count)"
            + " (\(String(format: "%.3f", Double(samples.count) / 16_000)) s)\nnon-zero: \(nonZero)"
            + "\npeak: \(samples.map(abs).max() ?? 0)\n"
        try? WAV.data(samples: samples).write(to: out)
        try? log.write(to: out.appendingPathExtension("log"), atomically: true, encoding: .utf8)
        print(log, terminator: "")
        return log.contains("error:") ? 1 : 0
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer: [Float] = []
        func append(_ samples: [Float]) { lock.withLock { buffer += samples } }
        var samples: [Float] { lock.withLock { buffer } }
    }
}

/// `Shepit capture-test <seconds> <out-dir>` — a meeting's two streams at once, with a simulated dictation
/// from 3 s to 6 s. Writes call.wav, mic.wav (the meeting's mic stream), dictation.wav and capture.log.
enum CaptureTest {
    @MainActor
    static func run(arguments: [String]) async -> Int32 {
        guard arguments.count == 2, let seconds = Double(arguments[0]) else {
            print("usage: Shepit capture-test <seconds> <out-dir>")
            return 2
        }
        let dir = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let call = Collected(), mic = Collected()
        let tap = CallTap()
        let recorder = AudioRecorder()
        var log = "started: \(Date())\n"
        tap.onSamples = { call.append($0, at: $1) }
        tap.onFailure = { log += "tap failure: \($0)\n" }
        recorder.onDictationStart = { log += "dictation start: \($0)\n" }
        recorder.onDictationEnd = { log += "dictation end: \($0)\n" }
        recorder.onStreamLost = { log += "mic lost: \($0)\n" }
        var dictation: [Float] = []
        do {
            try tap.start()
            if let notice = try recorder.startStream(deviceName: "", onSamples: { mic.append($0, at: $1) }) { log += "mic notice: \(notice)\n" }
            try await Task.sleep(for: .seconds(3))
            _ = try recorder.start(deviceName: "")
            try await Task.sleep(for: .seconds(3))
            dictation = recorder.stop()
            try await Task.sleep(for: .seconds(max(0, seconds - 6)))
        } catch {
            log += "error: \(error)\n"
        }
        recorder.stopStream()
        tap.stop()
        for (name, collected) in [("call", call), ("mic", mic)] {
            log += "\(name): \(collected.samples.count) samples (\(String(format: "%.3f", Double(collected.samples.count) / 16_000)) s), index gaps: \(collected.gaps)\n"
            try? WAV.data(samples: collected.samples).write(to: dir.appending(path: "\(name).wav"))
        }
        log += "dictation: \(dictation.count) samples (\(String(format: "%.3f", Double(dictation.count) / 16_000)) s)\ntap restarts: \(tap.restarts)\ntap filled: \(String(format: "%.2f", tap.filledSeconds)) s\n"
        try? WAV.data(samples: dictation).write(to: dir.appending(path: "dictation.wav"))
        try? log.write(to: dir.appending(path: "capture.log"), atomically: true, encoding: .utf8)
        print(log, terminator: "")
        return log.contains("error:") ? 1 : 0
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer: [Float] = []
        private var gapCount = 0
        func append(_ samples: [Float], at index: Int) {
            lock.withLock {
                if index != buffer.count { gapCount += 1 }
                buffer += samples
            }
        }
        var samples: [Float] { lock.withLock { buffer } }
        var gaps: Int { lock.withLock { gapCount } }
    }
}
