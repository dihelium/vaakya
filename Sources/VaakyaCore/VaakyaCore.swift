/// VaakyaCore — pure, testable logic for the Vaakya dictation app.
///
/// Hard rules (VAAKYA_BUILD_PLAN.md §2):
/// - No networking in this target. Ever.
/// - No AppKit/SwiftUI imports — this target is platform-light and unit-tested.
public enum VaakyaCore {
    public static let version = "0.1.0"
}
