import CoreAudio
import Foundation
import ShepitCore

/// Which processes hold the microphone, as Core Audio reports it (call offer design §4.1, §5.1): needs no
/// permission and reads no audio. Reports every process; `CallSource` decides which ones matter.
///
/// It re-reads the flags once a second: Core Audio's property listeners missed every change on a real
/// Teams call (2026-11-12). Lives as long as the app: there is no stop.
final class CallWatch: @unchecked Sendable {
    enum Change: Sendable { case took(bundleID: String, pid: pid_t), released(pid: pid_t) }

    private let onChange: @Sendable (Change) -> Void
    private let queue = DispatchQueue(label: "dev.shepit.callwatch")
    private var holders: [pid_t: String] = [:]
    private var timer: DispatchSourceTimer?

    /// `onChange` is called on the watch's own queue.
    init(onChange: @escaping @Sendable (Change) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1)
            timer.setEventHandler { [weak self] in self?.refresh() }
            timer.resume()
            self.timer = timer
        }
    }

    private func refresh() {
        var now: [pid_t: String] = [:]
        // A read that fails (the process just exited) counts as not holding the microphone.
        for process in Self.processes() where Self.number(process, kAudioProcessPropertyIsRunningInput) ?? 0 != 0 {
            guard let pid = Self.number(process, kAudioProcessPropertyPID) else { continue }
            now[pid_t(bitPattern: pid)] = Self.bundleID(process)
        }
        for (pid, bundleID) in now where holders[pid] == nil { onChange(.took(bundleID: bundleID, pid: pid)) }
        for pid in holders.keys where now[pid] == nil { onChange(.released(pid: pid)) }
        holders = now
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func number(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func bundleID(_ object: AudioObjectID) -> String {
        var address = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }

    private static func processes() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}

/// `Shepit call-watch`: prints microphone changes as the app will see them. Ctrl-C to stop.
enum CallWatchTest {
    static func run() {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss.SSS"
        let watch = CallWatch { change in
            let text = switch change {
            case .took(let bundleID, let pid): "took      pid \(pid) \(bundleID)  → \(CallSource(bundleID: bundleID).map { "\($0)" } ?? "ignored")"
            case .released(let pid): "released  pid \(pid)"
            }
            print("\(clock.string(from: Date())) \(text)")
            fflush(stdout)
        }
        watch.start()
        print("Watching which apps hold the microphone; Ctrl-C to stop")
        dispatchMain()
    }
}
