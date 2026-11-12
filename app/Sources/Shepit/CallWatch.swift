import CoreAudio
import Foundation
import ShepitCore

/// Which processes hold the microphone, as Core Audio reports it (call offer design §4.1, §5.1): needs no
/// permission and reads no audio. Reports every process; `CallSource` decides which ones matter.
///
/// It re-reads the flags when Core Audio says something changed (`poll: false`), or once a second
/// (`poll: true`, what the probe did). Lives as long as the app: there is no stop.
final class CallWatch: @unchecked Sendable {
    enum Change: Sendable { case took(bundleID: String, pid: pid_t), released(pid: pid_t) }

    private let poll: Bool
    private let onChange: @Sendable (Change) -> Void
    private let queue = DispatchQueue(label: "dev.shepit.callwatch")
    private var holders: [pid_t: String] = [:]
    private var listened: Set<AudioObjectID> = []
    private var timer: DispatchSourceTimer?

    /// `onChange` is called on the watch's own queue.
    init(poll: Bool, onChange: @escaping @Sendable (Change) -> Void) {
        self.poll = poll
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            if poll {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + 1, repeating: 1)
                timer.setEventHandler { [weak self] in self?.refresh() }
                timer.resume()
                self.timer = timer
            } else {
                listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            }
            refresh()
        }
    }

    /// Reads the flags again now (after wake from sleep).
    func check() { queue.async { [weak self] in self?.refresh() } }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
        var address = Self.address(selector)
        AudioObjectAddPropertyListenerBlock(object, &address, queue) { [weak self] _, _ in self?.refresh() }
    }

    private func refresh() {
        let processes = Self.processes()
        if !poll {
            // A process object goes away with its process, and its listener with it.
            for process in processes where !listened.contains(process) { listen(process, kAudioProcessPropertyIsRunningInput) }
            listened = Set(processes)
        }
        var now: [pid_t: String] = [:]
        for process in processes where Self.number(process, kAudioProcessPropertyIsRunningInput) != 0 {
            now[pid_t(bitPattern: Self.number(process, kAudioProcessPropertyPID))] = Self.bundleID(process)
        }
        for (pid, bundleID) in now where holders[pid] == nil { onChange(.took(bundleID: bundleID, pid: pid)) }
        for pid in holders.keys where now[pid] == nil { onChange(.released(pid: pid)) }
        holders = now
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func number(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
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

/// `Shepit call-watch`: prints microphone changes as the listeners see them and as a once-a-second check
/// sees them, side by side, to tell whether listeners alone can be trusted (plan Task 3). Ctrl-C to stop.
enum CallWatchTest {
    static func run() {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss.SSS"
        func printer(_ tag: String) -> @Sendable (CallWatch.Change) -> Void {
            { change in
                let text = switch change {
                case .took(let bundleID, let pid): "took      pid \(pid) \(bundleID)  → \(CallSource(bundleID: bundleID).map { "\($0)" } ?? "ignored")"
                case .released(let pid): "released  pid \(pid)"
                }
                print("\(clock.string(from: Date())) \(tag) \(text)")
                fflush(stdout)
            }
        }
        let listeners = CallWatch(poll: false, onChange: printer("listener"))
        let check = CallWatch(poll: true, onChange: printer("check   "))
        listeners.start()
        check.start()
        print("Watching which apps hold the microphone; Ctrl-C to stop")
        dispatchMain()
    }
}
