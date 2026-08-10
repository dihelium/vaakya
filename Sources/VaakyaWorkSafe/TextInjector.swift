import AppKit
import CoreGraphics

/// Types Unicode directly. Work-safe mode never reads or writes the clipboard
/// and never observes the target application's text contents.
final class TextInjector {
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func inject(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            var end = min(index + 20, units.count)
            if end < units.count,
               (0xD800...0xDBFF).contains(units[end - 1]),
               (0xDC00...0xDFFF).contains(units[end]) {
                end -= 1
            }
            let chunk = Array(units[index..<end])
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                chunk.withUnsafeBufferPointer { buffer in
                    down.keyboardSetUnicodeString(
                        stringLength: buffer.count,
                        unicodeString: buffer.baseAddress!
                    )
                    up.keyboardSetUnicodeString(
                        stringLength: buffer.count,
                        unicodeString: buffer.baseAddress!
                    )
                }
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            index = end
        }
    }
}
