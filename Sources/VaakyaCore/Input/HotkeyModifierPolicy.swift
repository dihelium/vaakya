import CoreGraphics

/// Defines which concurrently pressed modifiers participate in hotkey
/// exclusivity. Lock states such as Caps Lock are intentionally ignored.
public enum HotkeyModifierPolicy {
    public static let activationModifiers: CGEventFlags = [
        .maskCommand,
        .maskShift,
        .maskAlternate,
        .maskControl,
        .maskSecondaryFn,
    ]

    /// A modifier hotkey is eligible only when it is the sole pressed modifier.
    public static func allowsActivation(activeFlags: CGEventFlags,
                                        hotkeyFlag: CGEventFlags) -> Bool {
        activeFlags.intersection(activationModifiers) == hotkeyFlag
    }
}
