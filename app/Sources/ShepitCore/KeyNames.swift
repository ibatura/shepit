import Carbon.HIToolbox

/// Key and modifier names as settings.json uses them (Hammerspoon's names) → Carbon key codes.
/// Codes are physical (ANSI positions), so a hotkey works the same in any keyboard layout.
public enum KeyNames {
    public static func keyCode(_ name: String) -> UInt32? {
        codes[name.lowercased()].map(UInt32.init)
    }

    /// The settings.json name of a physical key code, for the shortcut recorder.
    public static func name(forKeyCode code: UInt32) -> String? {
        names[Int(code)]
    }

    public static func modifiers(_ mods: [String]) -> UInt32 {
        mods.reduce(0) { flags, mod in
            switch mod {
            case "cmd": flags | UInt32(cmdKey)
            case "alt": flags | UInt32(optionKey)
            case "ctrl": flags | UInt32(controlKey)
            case "shift": flags | UInt32(shiftKey)
            default: flags
            }
        }
    }

    /// `alt+space`, as the Lua tool showed it.
    public static func label(_ hotkey: Hotkey) -> String {
        (hotkey.mods + [hotkey.key]).joined(separator: "+")
    }

    // Several names may share a code ("delete"/…); any one is fine for writing settings.
    private static let names: [Int: String] = Dictionary(codes.map { ($0.value, $0.key) }, uniquingKeysWith: { min($0, $1) })

    private static let codes: [String: Int] = {
        var codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
            "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape,
            "delete": kVK_Delete, "forwarddelete": kVK_ForwardDelete, "help": kVK_Help,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "padenter": kVK_ANSI_KeypadEnter, "pad.": kVK_ANSI_KeypadDecimal, "pad*": kVK_ANSI_KeypadMultiply,
            "pad+": kVK_ANSI_KeypadPlus, "pad/": kVK_ANSI_KeypadDivide, "pad-": kVK_ANSI_KeypadMinus,
            "pad=": kVK_ANSI_KeypadEquals, "padclear": kVK_ANSI_KeypadClear,
        ]
        let pad = [kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
                   kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        for (digit, code) in pad.enumerated() { codes["pad\(digit)"] = code }
        let function = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in function.enumerated() { codes["f\(index + 1)"] = code }
        return codes
    }()
}
