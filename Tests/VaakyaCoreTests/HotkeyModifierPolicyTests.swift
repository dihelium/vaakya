import CoreGraphics
import Testing
@testable import VaakyaCore

@Suite struct HotkeyModifierPolicyTests {
    @Test func optionAloneIsAllowed() {
        #expect(HotkeyModifierPolicy.allowsActivation(activeFlags: .maskAlternate,
                                                       hotkeyFlag: .maskAlternate))
    }

    @Test(arguments: [
        CGEventFlags.maskCommand,
        .maskShift,
        .maskControl,
        .maskSecondaryFn,
    ])
    func optionWithAnotherPressedModifierIsRejected(otherModifier: CGEventFlags) {
        let chord: CGEventFlags = [.maskAlternate, otherModifier]
        #expect(!HotkeyModifierPolicy.allowsActivation(activeFlags: chord,
                                                        hotkeyFlag: .maskAlternate))
    }

    @Test func anotherModifierWithoutOptionIsRejected() {
        #expect(!HotkeyModifierPolicy.allowsActivation(activeFlags: .maskCommand,
                                                        hotkeyFlag: .maskAlternate))
    }

    @Test func capsLockStateDoesNotBlockOption() {
        let flags: CGEventFlags = [.maskAlternate, .maskAlphaShift]
        #expect(HotkeyModifierPolicy.allowsActivation(activeFlags: flags,
                                                       hotkeyFlag: .maskAlternate))
    }
}
