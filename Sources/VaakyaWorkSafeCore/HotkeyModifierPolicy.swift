import CoreGraphics

/// The dictation hotkey activates only when Left Option is the sole modifier.
public enum HotkeyModifierPolicy {
    public static let activationModifiers: CGEventFlags = [
        .maskCommand,
        .maskShift,
        .maskAlternate,
        .maskControl,
        .maskSecondaryFn,
    ]

    public static func allowsActivation(
        activeFlags: CGEventFlags,
        hotkeyFlag: CGEventFlags
    ) -> Bool {
        activeFlags.intersection(activationModifiers) == hotkeyFlag
    }
}
