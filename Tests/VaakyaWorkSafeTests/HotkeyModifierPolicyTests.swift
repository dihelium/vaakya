import CoreGraphics
import Testing
@testable import VaakyaCore

@Suite("Work-safe hotkey isolation")
struct HotkeyModifierPolicyTests {
    @Test("Left Option alone is accepted")
    func optionOnly() {
        #expect(HotkeyModifierPolicy.allowsActivation(
            activeFlags: .maskAlternate,
            hotkeyFlag: .maskAlternate
        ))
    }

    @Test("Modifier chords are rejected")
    func modifierChord() {
        #expect(!HotkeyModifierPolicy.allowsActivation(
            activeFlags: [.maskAlternate, .maskCommand],
            hotkeyFlag: .maskAlternate
        ))
    }
}
