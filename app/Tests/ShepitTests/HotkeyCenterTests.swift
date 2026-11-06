import Carbon.HIToolbox
import Testing
@testable import Shepit
import ShepitCore

@MainActor
private final class FakeRegistrar: HotkeyRegistrar {
    var handler: ((UInt32, Bool) -> Void)?
    var active: [UInt32: (UInt32, UInt32)] = [:]
    var refuse: Set<UInt32> = [] // key codes another app holds

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
        guard !refuse.contains(keyCode) else { return false }
        active[id] = (keyCode, modifiers)
        return true
    }

    func unregister(id: UInt32) { active[id] = nil }
}

@MainActor
struct HotkeyCenterTests {
    @Test func registersDictationAndAddWordButNotCancel() {
        let registrar = FakeRegistrar()
        let center = HotkeyCenter(registrar: registrar)
        #expect(center.apply(.defaults) == .active)
        #expect(registrar.active.count == 2)
        #expect(registrar.active.values.contains { $0 == (UInt32(kVK_Space), UInt32(optionKey)) })
        #expect(registrar.active.values.contains { $0 == (UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey)) })
    }

    @Test func cancelKeyOnlyWhileRecording() {
        let registrar = FakeRegistrar()
        let center = HotkeyCenter(registrar: registrar)
        center.apply(.defaults)
        center.setCancelEnabled(true)
        #expect(registrar.active.values.contains { $0 == (UInt32(kVK_Escape), 0) })
        center.setCancelEnabled(false)
        #expect(!registrar.active.values.contains { $0 == (UInt32(kVK_Escape), 0) })
    }

    @Test func settingsReloadWhileRecordingKeepsTheCancelKey() {
        let registrar = FakeRegistrar()
        let center = HotkeyCenter(registrar: registrar)
        center.apply(.defaults)
        center.setCancelEnabled(true)
        center.apply(.defaults)
        #expect(registrar.active.values.contains { $0 == (UInt32(kVK_Escape), 0) })
    }

    @Test func suspendForTheShortcutRecorderAndApplyAgain() {
        let registrar = FakeRegistrar()
        let center = HotkeyCenter(registrar: registrar)
        center.apply(.defaults)
        center.suspend()
        #expect(registrar.active.isEmpty)
        center.apply(.defaults)
        #expect(registrar.active.count == 2)
    }

    @Test func pressAndReleaseReachTheController() {
        let registrar = FakeRegistrar()
        let center = HotkeyCenter(registrar: registrar)
        var events: [String] = []
        center.onDictationDown = { events.append("down") }
        center.onDictationUp = { events.append("up") }
        center.onCancel = { events.append("cancel") }
        center.onAddWord = { events.append("add") }
        center.apply(.defaults)
        for (id, pressed) in [(1, true), (1, false), (2, true), (3, true), (3, false)] {
            registrar.handler?(UInt32(id), pressed)
        }
        #expect(events == ["down", "up", "cancel", "add"])
    }

    @Test func failuresUseTheLuaMessages() {
        let registrar = FakeRegistrar()
        registrar.refuse = [UInt32(kVK_Space)]
        var settings = Settings.defaults
        settings.cancelKey = "nope"
        settings.addWordHotkey = Hotkey(mods: ["ctrl"], key: "nope")
        let center = HotkeyCenter(registrar: registrar)
        #expect(center.apply(settings) == .failed([
            #"cannot bind hotkey alt+space — change "hotkey" in settings.json"#,
            #"invalid cancelKey "nope" in settings.json"#,
            "cannot bind addWordHotkey ctrl+nope — change it in settings.json",
        ]))
    }

    @Test func reapplyingReRegistersWithNewSettings() {
        let registrar = FakeRegistrar()
        let center = HotkeyCenter(registrar: registrar)
        center.apply(.defaults)
        var settings = Settings.defaults
        settings.hotkey = Hotkey(mods: ["cmd", "shift"], key: "d")
        center.apply(settings)
        #expect(registrar.active[1].map { $0 == (UInt32(kVK_ANSI_D), UInt32(cmdKey | shiftKey)) } == true)
        #expect(registrar.active.count == 2)
    }

}
