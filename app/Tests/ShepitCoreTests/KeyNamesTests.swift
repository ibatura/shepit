import Carbon.HIToolbox
import Testing
@testable import ShepitCore

struct KeyNamesTests {
    @Test func defaultHotkeysMap() {
        #expect(KeyNames.keyCode("space") == UInt32(kVK_Space))
        #expect(KeyNames.modifiers(["alt"]) == UInt32(optionKey))
        #expect(KeyNames.keyCode("d") == UInt32(kVK_ANSI_D))
        #expect(KeyNames.modifiers(["ctrl", "alt"]) == UInt32(controlKey | optionKey))
        #expect(KeyNames.keyCode("escape") == UInt32(kVK_Escape))
    }

    @Test func everyModifierTheValidatorAcceptsMaps() {
        #expect(KeyNames.modifiers(["cmd", "alt", "ctrl", "shift"]) == UInt32(cmdKey | optionKey | controlKey | shiftKey))
    }

    @Test func namesAreCaseInsensitiveAndUnknownNamesAreNil() {
        #expect(KeyNames.keyCode("F5") == UInt32(kVK_F5))
        #expect(KeyNames.keyCode("pad7") == UInt32(kVK_ANSI_Keypad7))
        #expect(KeyNames.keyCode("hyper") == nil)
    }

    @Test func everyKeyCodeMapsBackToANameThatMapsToItAgain() {
        for name in ["space", "d", "f13", "escape", "pad7", "/", "return"] {
            let code = KeyNames.keyCode(name)!
            #expect(KeyNames.keyCode(KeyNames.name(forKeyCode: code)!) == code)
        }
        #expect(KeyNames.name(forKeyCode: UInt32(kVK_Space)) == "space")
    }

    @Test func labelMatchesTheLuaTool() {
        #expect(KeyNames.label(Hotkey(mods: ["ctrl", "alt"], key: "d")) == "ctrl+alt+d")
    }
}
