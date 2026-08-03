import AppKit
import ApplicationServices
import Foundation
import VaakyaCore

/// Passive correction capture (plan §5.4): after injection, watch the focused
/// element's AXValue; on change, diff injected vs edited text and record
/// `corrections` rows + `suggested` rules. Silently skips unreadable elements
/// (Electron/web fields that don't expose AX text).
@MainActor
final class EditWatcher: NSObject {
    private let db: VaakyaDatabase
    private let injectedText: String
    private let dictationId: Int64?
    private let appContext: String?

    private var observer: AXObserver?
    private var element: AXUIElement?
    private var appElement: AXUIElement?
    private var valueBeforeInjection: String?
    private var finalValue: String?
    private var isArmed = false
    private var observesFocusChanges = false
    private var windowTimer: Timer?
    private var finished = false

    /// Window length: 90 s (plan §5.4).
    private static let windowDuration: TimeInterval = 90

    /// C callback bridged to the watcher instance via userInfo.
    private static let axCallback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let watcher = Unmanaged<EditWatcher>.fromOpaque(refcon).takeUnretainedValue()
        let isFocusChange = notification as String == kAXFocusedUIElementChangedNotification
        Task { @MainActor in
            if isFocusChange {
                watcher.finish()
            } else {
                watcher.handleChange()
            }
        }
    }

    init(db: VaakyaDatabase, injectedText: String, dictationId: Int64?, appContext: String?) {
        self.db = db
        self.injectedText = injectedText
        self.dictationId = dictationId
        self.appContext = appContext
    }

    func begin() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            finish()
            return
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = focusedElement(of: appElement) else {
            finish()
            return
        }
        self.appElement = appElement
        self.element = element
        valueBeforeInjection = axValue(of: element)
        guard valueBeforeInjection != nil else {
            // Unreadable element — silently skip (plan §5.4 guard).
            finish()
            return
        }
        let pid = app.processIdentifier
        var obs: AXObserver?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverCreate(pid, Self.axCallback, &obs) == .success, let obs else {
            finish()
            return
        }
        observer = obs
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        var name = kAXValueChangedNotification as CFString
        guard AXObserverAddNotification(obs, element, name, selfPtr) == .success else {
            finish()
            return
        }
        name = kAXFocusedUIElementChangedNotification as CFString
        observesFocusChanges = AXObserverAddNotification(obs, appElement, name, selfPtr) == .success
        windowTimer = Timer.scheduledTimer(withTimeInterval: Self.windowDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish() }
        }
    }

    func cancel() {
        finish()
    }

    private func handleChange() {
        guard let element, let current = axValue(of: element) else { return }
        finalValue = current
        if !isArmed,
           current != valueBeforeInjection,
           current.contains(injectedText) {
            // Unicode injection arrives in chunks. Do not treat those partial
            // AX changes as user edits or end the learning window early.
            isArmed = true
        }
    }

    /// Diff the injected transcript against the value at the end of the edit
    /// window and record one piece of learning evidence.
    private func learn(from before: String, to after: String) {
        // Whole-text deletion teaches nothing (plan §5.4).
        guard !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard before != after else { return }
        let result = DiffLearner.diff(asrText: before, editedText: after)
        guard !result.isWholesaleRewrite else { return }
        _ = try? db.insertCorrection(dictationId: dictationId,
                                     asrText: before,
                                     editedText: after,
                                     capture: "passive_ax",
                                     appContext: appContext)
        for candidate in result.candidates {
            try? db.upsertReplacementRule(
                ReplacementRule(match: candidate.match,
                                replacement: candidate.replacement,
                                matchKind: candidate.matchKind),
                source: "learned_passive",
                status: "suggested")
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if let element, let current = axValue(of: element) {
            finalValue = current
            if !isArmed,
               current != valueBeforeInjection,
               current.contains(injectedText) {
                isArmed = true
            }
        }
        windowTimer?.invalidate()
        windowTimer = nil
        if let observer, let element {
            let name = kAXValueChangedNotification as CFString
            AXObserverRemoveNotification(observer, element, name)
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(observer),
                                  .commonModes)
        }
        if observesFocusChanges, let observer, let appElement {
            let name = kAXFocusedUIElementChangedNotification as CFString
            AXObserverRemoveNotification(observer, appElement, name)
        }
        observer = nil
        self.element = nil
        self.appElement = nil
        EditWatcherManager.shared.currentWatcherDidFinish()
        if isArmed, let finalValue {
            learn(from: injectedText, to: finalValue)
        }
    }

    // MARK: - AX helpers

    private func focusedElement(of appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success else {
            return nil
        }
        return (value as! AXUIElement?) ?? nil
    }

    private func axValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}

/// Tracks the one active edit window (plan §5.4: "Window ends on focus change,
/// 90 s timeout, or next dictation").
@MainActor
final class EditWatcherManager {
    static let shared = EditWatcherManager()
    private(set) var currentWatcher: EditWatcher?

    func startWatcher(db: VaakyaDatabase, injectedText: String, dictationId: Int64?, appContext: String?) {
        currentWatcher?.cancel()
        let watcher = EditWatcher(db: db, injectedText: injectedText, dictationId: dictationId, appContext: appContext)
        currentWatcher = watcher
        watcher.begin()
    }

    func currentWatcherDidFinish() {
        currentWatcher = nil
    }
}
