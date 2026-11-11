// Research tool for "offer to record when a call starts" (docs/future-ideas.md).
// Prints, once a second, every change in which processes use the microphone or play sound,
// as Core Audio reports it. Reads process names and two flags only: no audio, no text.
// Needs no permission. Run during a call:  swift tools/call-probe/probe.swift
// Stop with Ctrl-C.
import CoreAudio
import Foundation

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

func number(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
    var a = address(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value)
    return value
}

func bundleID(_ id: AudioObjectID) -> String {
    var a = address(kAudioProcessPropertyBundleID)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let value else { return "?" }
    return value.takeRetainedValue() as String
}

func processes() -> [AudioObjectID] {
    var a = address(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

let clock = DateFormatter()
clock.dateFormat = "HH:mm:ss"
var last: [String: String] = [:]
print("\(clock.string(from: Date())) watching \(processes().count) audio processes; Ctrl-C to stop")
while true {
    var now: [String: String] = [:]
    for id in processes() {
        let input = number(id, kAudioProcessPropertyIsRunningInput) != 0
        let output = number(id, kAudioProcessPropertyIsRunningOutput) != 0
        guard input || output else { continue }
        let key = "\(bundleID(id)) pid \(number(id, kAudioProcessPropertyPID))"
        now[key] = (input ? "mic " : "") + (output ? "sound" : "")
    }
    for (key, state) in now where last[key] != state {
        print("\(clock.string(from: Date())) \(key): \(state)")
    }
    for key in last.keys where now[key] == nil {
        print("\(clock.string(from: Date())) \(key): stopped")
    }
    last = now
    fflush(stdout)
    sleep(1)
}
