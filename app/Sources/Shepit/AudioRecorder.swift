@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import ShepitCore

/// Records the microphone into memory as 16 kHz mono Float32 (`03-dictation.md` §2). No temp files.
///
/// AVCaptureSession, not AVAudioEngine: switching the input device on an AVAudioEngine hung the main
/// thread (fresh engine per recording) or delivered garbage in the old device's format (one engine), and
/// a kept engine held a Bluetooth headset in its call mode. A capture session selects devices by ID,
/// converts to our format itself, and releases the microphone when it stops.
///
/// During a meeting the session stays open for the whole call (`startStream`): every sample goes to the
/// meeting with its stream index, and a dictation records a slice of the same input (`start`/`stop` don't
/// touch the session then) and reports where it began and ended, so the meeting can leave it out (spec §5.8).
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Device: Equatable {
        let id: AudioDeviceID
        let name: String
        let uid: String
    }

    /// Called on the main queue when recording stopped on its own: `samples` is what was recorded
    /// (transcribe it), or nil when nothing usable is left.
    var onLost: (@MainActor (_ message: String, _ samples: [Float]?) -> Void)?

    private let lock = NSLock()
    private var samples: [Float] = [] // the dictation being recorded
    private var dictating = false
    private var streamIndex = 0
    private var stream: (@Sendable (_ samples: [Float], _ firstIndex: Int) -> Void)?
    /// When the device was lost mid-meeting: the next block first pads the stream with that much silence,
    /// so its index stays close to real time like the call stream's.
    private var gapFrom: Date?
    /// Meeting callbacks, on the main queue: a dictation started / ended at this stream index.
    var onDictationStart: (@MainActor (Int) -> Void)?
    /// The meeting stream's index right now (for a mute change in the call app).
    var streamPosition: Int { lock.withLock { streamIndex } }
    var onDictationEnd: (@MainActor (Int) -> Void)?
    /// The meeting's microphone stream could not continue (device gone and no default to switch to).
    var onStreamLost: (@MainActor (String) -> Void)?

    var isStreaming: Bool { lock.withLock { stream != nil } }

    private var session: AVCaptureSession?
    private var chosenUID: String?
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "dev.shepit.recorder")

    /// Real input devices by name, meeting-app loopbacks hidden.
    static func inputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let name = string(id, kAudioObjectPropertyName), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  !Microphones.isVirtual(name: name, uid: uid) else { return nil }
            return Device(id: id, name: name, uid: uid)
        }
    }

    /// Starts recording from `deviceName` (empty = system default). Returns a notice when the
    /// configured device isn't connected and the default is used instead.
    @MainActor
    func start(deviceName: String) throws -> String? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw RecorderError("allow microphone access for Shepit, then try again")
        default:
            throw RecorderError("no microphone access — System Settings → Privacy & Security → Microphone → Shepit")
        }
        if session != nil { // a meeting holds the microphone: record a slice of it
            let (index, already) = lock.withLock {
                let already = dictating
                samples.removeAll(keepingCapacity: true)
                dictating = true
                return (streamIndex, already)
            }
            if !already { onDictationStart?(index) }
            return nil
        }
        let pick = choose(deviceName)
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            dictating = true // before begin(): its first blocks belong to the dictation
        }
        do {
            try begin()
        } catch {
            lock.withLock { dictating = false }
            throw error
        }
        return pick
    }

    /// Stops and returns everything recorded.
    @MainActor
    func stop() -> [Float] {
        let (recorded, index, was) = lock.withLock {
            let was = dictating
            dictating = false
            return (samples, streamIndex, was)
        }
        if isStreaming {
            if was { onDictationEnd?(index) }
        } else {
            end()
        }
        return recorded
    }

    @MainActor
    func cancel() {
        let (index, was) = lock.withLock {
            let was = dictating
            dictating = false
            samples.removeAll()
            return (streamIndex, was)
        }
        if isStreaming {
            if was { onDictationEnd?(index) }
        } else {
            end()
        }
    }

    /// Opens the microphone for a meeting; `onSamples` gets every block on the recorder's queue.
    /// A dictation already recording keeps going on its device and is skipped from index 0.
    @MainActor
    func startStream(deviceName: String, onSamples: @escaping @Sendable (_ samples: [Float], _ firstIndex: Int) -> Void) throws -> String? {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError("no microphone access — System Settings → Privacy & Security → Microphone → Shepit")
        }
        let wasDictating = lock.withLock {
            streamIndex = 0
            gapFrom = nil
            stream = onSamples
            return dictating
        }
        if session != nil {
            if wasDictating { onDictationStart?(0) }
            return nil
        }
        let notice = choose(deviceName)
        do {
            try begin()
        } catch {
            lock.withLock { stream = nil }
            throw error
        }
        return notice
    }

    /// Releases the meeting's hold; the microphone stays open only while a dictation still records.
    @MainActor
    func stopStream() {
        let keep = lock.withLock {
            stream = nil
            return dictating
        }
        if !keep { end() }
    }

    private func choose(_ deviceName: String) -> String? {
        let devices = Self.inputDevices()
        let pick = Microphones.pick(deviceName, available: devices.map(\.name))
        chosenUID = devices.first { $0.name == pick.device }?.uid
        return pick.notice
    }

    /// The newest `count` samples, for the meter and the live draft.
    func tail(_ count: Int) -> [Float] {
        lock.withLock { Array(samples.suffix(count)) }
    }

    private func begin() throws {
        let device = chosenUID.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw RecorderError("no input device") }
        let session = AVCaptureSession()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecorderError("could not open \(device.localizedName): \(error.localizedDescription)")
        }
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecorderError("could not record from \(device.localizedName)")
        }
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
        guard session.isRunning else { throw RecorderError("could not start recording from \(device.localizedName)") }
        self.session = session
        observe(session, device)
    }

    private func end() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        session?.stopRunning()
        session = nil
    }

    /// The device went away (Bluetooth off, headset unplugged) or the session failed.
    private func observe(_ session: AVCaptureSession, _ device: AVCaptureDevice) {
        let center = NotificationCenter.default
        let watched: [(Notification.Name, AnyObject)] = [
            (AVCaptureDevice.wasDisconnectedNotification, device),
            (AVCaptureSession.runtimeErrorNotification, session),
        ]
        let watchedSession = ObjectIdentifier(session)
        for (name, object) in watched {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // A notification queued for a session that is already gone must not move the new one.
                    guard let self, self.session.map(ObjectIdentifier.init) == watchedSession else { return }
                    self.deviceLost()
                }
            })
        }
    }

    /// Continue on the system default if possible; otherwise stop and hand over what was recorded.
    @MainActor
    private func deviceLost() {
        guard session != nil else { return }
        end()
        chosenUID = nil
        lock.withLock { if stream != nil { gapFrom = Date() } }
        do {
            try begin()
        } catch {
            let (recorded, wasDictating, wasStreaming) = lock.withLock {
                let state = (samples, dictating, stream != nil)
                dictating = false
                stream = nil
                return state
            }
            if wasStreaming { onStreamLost?("Microphone disconnected") }
            if wasDictating { onLost?("Microphone disconnected", recorded.isEmpty ? nil : recorded) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var blockBuffer: CMBlockBuffer?
        var list = AudioBufferList()
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list, bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer) == noErr,
            let data = list.mBuffers.mData else { return }
        let chunk = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: Int(list.mBuffers.mDataByteSize) / 4)
        let (stream, first, gap) = lock.withLock {
            var gap = 0
            if let gapFrom {
                gap = Int(Date().timeIntervalSince(gapFrom) * 16_000)
                self.gapFrom = nil
            }
            if dictating { samples.append(contentsOf: chunk) }
            let first = streamIndex
            streamIndex += gap + chunk.count
            return (self.stream, first, gap)
        }
        if gap > 0 { stream?([Float](repeating: 0, count: gap), first) }
        stream?(Array(chunk), first + gap)
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

struct RecorderError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
