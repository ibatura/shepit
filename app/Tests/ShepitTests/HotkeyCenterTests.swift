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


    @Test func theMeetingHotkeyIsRegisteredOnlyWhenSetAndReachesItsHandler() {
        let registrar = FakeRegistrar()
        let center = HotkeyCenter(registrar: registrar)
        var presses = 0
        center.onMeeting = { presses += 1 }
        var settings = Settings.defaults
        settings.meetingHotkey = Hotkey(mods: ["ctrl", "alt"], key: "m")
        #expect(center.apply(settings) == .active)
        #expect(registrar.active[4].map { $0 == (UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey)) } == true)
        registrar.handler?(4, true)
        registrar.handler?(4, false)
        #expect(presses == 1)

        settings.meetingHotkey = nil // removed in Settings
        #expect(center.apply(settings) == .active)
        #expect(registrar.active[4] == nil && registrar.active.count == 2)
    }

    @Test func aMeetingHotkeyThatClashesIsLeftOutAndReported() {
        let registrar = FakeRegistrar()
        let center = HotkeyCenter(registrar: registrar)
        var settings = Settings.defaults
        let taken = [(settings.hotkey, "dictation hotkey"), (settings.addWordHotkey, "add-word hotkey"),
                     (Hotkey(mods: ["alt", "ctrl"], key: "D"), "add-word hotkey")] // any order, any case
        for (hotkey, name) in taken {
            settings.meetingHotkey = hotkey
            #expect(center.apply(settings) == .failed([
                "meetingHotkey \(KeyNames.label(hotkey)): That is the \(name) — change it in Settings → Hotkeys",
            ]))
            #expect(registrar.active.count == 2 && registrar.active[4] == nil)
        }
        registrar.refuse = [UInt32(kVK_ANSI_M)] // another app holds it
        settings.meetingHotkey = Hotkey(mods: ["ctrl"], key: "m")
        #expect(center.apply(settings) == .failed(["cannot bind meetingHotkey ctrl+m — change it in Settings → Hotkeys"]))
    }
}
