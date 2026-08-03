import AppKit
import CoreGraphics
import Foundation

/// Types text at the cursor (plan §6). Primary: Unicode CGEvent key events,
/// chunked ≤20 UniChars per event. Fallback: pasteboard → Cmd+V → restore.
final class TextInjector {
    enum InjectionMethod: String, CaseIterable {
        case auto, unicode, paste
    }

    private let method: InjectionMethod

    init(method: InjectionMethod) {
        self.method = method
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func inject(_ text: String) {
        switch method {
        case .paste:
            paste(text)
        case .unicode:
            unicodeInject(text)
        case .auto:
            unicodeInject(text)
        }
    }

    /// CGEventKeyboardSetUnicodeString — handles all Unicode without touching the clipboard.
    private func unicodeInject(_ text: String) {
        let chunkSize = 20
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            var end = min(index + chunkSize, units.count)
            if end < units.count,
               (0xD800...0xDBFF).contains(units[end - 1]),
               (0xDC00...0xDFFF).contains(units[end]) {
                end -= 1
            }
            let chunk = Array(units[index..<end])
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                chunk.withUnsafeBufferPointer { buf in
                    down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress!)
                    up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress!)
                }
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            index = end
        }
    }

    /// Pasteboard → Cmd+V → restore previous contents.
    /// Restore every original item/type, but only if nobody changed the board
    /// after Vaakya wrote the temporary dictated text.
    private func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map(PasteboardItemSnapshot.init) ?? []
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let injectedChangeCount = pasteboard.changeCount

        // Synthetic Cmd+V.
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // CGEvent delivery is asynchronous, so let the target consume the
        // temporary value before restoring the full prior pasteboard payload.
        let deadline = DispatchTime.now() + .milliseconds(400)
        DispatchQueue.main.asyncAfter(deadline: deadline) { [pasteboard] in
            guard pasteboard.changeCount == injectedChangeCount else { return }
            pasteboard.clearContents()
            let restored = previousItems.map(\.pasteboardItem)
            if !restored.isEmpty {
                pasteboard.writeObjects(restored)
            }
        }
    }

    private struct PasteboardItemSnapshot {
        let values: [(NSPasteboard.PasteboardType, Data)]

        init(_ item: NSPasteboardItem) {
            values = item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }

        var pasteboardItem: NSPasteboardItem {
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
    }
}
