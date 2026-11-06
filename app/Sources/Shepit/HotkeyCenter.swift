import Carbon.HIToolbox
import Foundation
import ShepitCore

/// Registers system-wide hotkeys; the real one wraps Carbon, tests fake it.
@MainActor
protocol HotkeyRegistrar: AnyObject {
    /// Called with the hotkey id and true on press, false on release.
    var handler: ((UInt32, Bool) -> Void)? { get set }
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool
    func unregister(id: UInt32)
}

/// Dictation, cancel and add-word hotkeys (port of bindHotkeys in init.lua).
@MainActor
final class HotkeyCenter {
    enum State: Equatable {
        case active
        case failed([String])
    }

    private enum ID: UInt32 {
        case dictation = 1, cancel, addWord
    }

    var onDictationDown: (() -> Void)?
    var onDictationUp: (() -> Void)?
    var onCancel: (() -> Void)?
    var onAddWord: (() -> Void)?
    private(set) var state = State.active

    private let registrar: any HotkeyRegistrar
    private var cancelKey: (code: UInt32, mods: UInt32)?
    private var registered: Set<ID> = []
    private var cancelWanted = false // survives a settings reload mid-recording

    init(registrar: any HotkeyRegistrar) {
        self.registrar = registrar
        registrar.handler = { [weak self] id, pressed in self?.handle(id, pressed) }
    }

    /// (Re)registers everything from the current settings.
    @discardableResult
    func apply(_ settings: Settings) -> State {
        for id in registered { registrar.unregister(id: id.rawValue) }
        registered = []
        cancelKey = nil
        var errors: [String] = []
        if !register(.dictation, settings.hotkey) {
            errors.append(#"cannot bind hotkey \#(KeyNames.label(settings.hotkey)) — change "hotkey" in settings.json"#)
        }
        if let code = KeyNames.keyCode(settings.cancelKey) {
            cancelKey = (code, 0) // registered only while recording
        } else {
            errors.append(#"invalid cancelKey "\#(settings.cancelKey)" in settings.json"#)
        }
        if !register(.addWord, settings.addWordHotkey) {
            errors.append("cannot bind addWordHotkey \(KeyNames.label(settings.addWordHotkey)) — change it in settings.json")
        }
        state = errors.isEmpty ? .active : .failed(errors)
        if cancelWanted { setCancelEnabled(true) }
        return state
    }

    /// While a shortcut is being recorded in Settings, so pressing it there doesn't trigger it.
    /// `apply` brings everything back.
    func suspend() {
        for id in registered { registrar.unregister(id: id.rawValue) }
        registered = []
    }

    /// The cancel key exists only while recording, so Esc works normally otherwise.
    func setCancelEnabled(_ on: Bool) {
        cancelWanted = on
        if on, let cancelKey, !registered.contains(.cancel),
           registrar.register(keyCode: cancelKey.code, modifiers: cancelKey.mods, id: ID.cancel.rawValue) {
            registered.insert(.cancel)
        } else if !on, registered.contains(.cancel) {
            registrar.unregister(id: ID.cancel.rawValue)
            registered.remove(.cancel)
        }
    }

    private func register(_ id: ID, _ hotkey: Hotkey) -> Bool {
        guard let code = KeyNames.keyCode(hotkey.key),
              registrar.register(keyCode: code, modifiers: KeyNames.modifiers(hotkey.mods), id: id.rawValue) else { return false }
        registered.insert(id)
        return true
    }

    private func handle(_ raw: UInt32, _ pressed: Bool) {
        switch (ID(rawValue: raw), pressed) {
        case (.dictation, true): onDictationDown?()
        case (.dictation, false): onDictationUp?()
        case (.cancel, true): onCancel?()
        case (.addWord, true): onAddWord?()
        default: break
        }
    }
}

/// Carbon `RegisterEventHotKey`, with press and release.
@MainActor
final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    var handler: ((UInt32, Bool) -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private static let signature: OSType = 0x5348_5054 // "SHPT"

    init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { registrar.handler?(hotkeyID.id, pressed) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
}
