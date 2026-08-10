import AppKit
import CoreGraphics
import Foundation
import VaakyaCore

/// CGEvent session event tap for the dictation hotkey (plan §6):
/// - modifier hotkeys activate only when no other pressed modifier is present
/// - hold ≥150 ms = record while held (observe-only, modifier not swallowed)
/// - optional double-tap = latch (record until next tap)
/// Requires Input Monitoring permission; `preflight` reports it.
///
/// The CGEvent callback and timer fire on background threads; all mutable state
/// is guarded by `lock`. Explicitly `@unchecked Sendable` because the C callback
/// and `DispatchSource` are outside the Swift concurrency model — the lock makes
/// it safe.
final class HotkeyMonitor: @unchecked Sendable {
    /// Events delivered on a serial queue; coalesced onto the main actor by the owner.
    enum Gesture: Equatable {
        case holdBegan
        case holdEnded
        case doubleTapBegan
        case latchEnded
        case singleTap
    }

    private let keyCode: CGKeyCode
    private let doubleTapEnabled: Bool

    private let lock = NSLock()
    private var onGestureHandler: ((Gesture) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdTimer: DispatchSourceTimer?
    private var isHeld = false
    private var isLatched = false
    private var ignoreNextKeyUp = false
    private var suppressHotkeyUntilRelease = false
    private var activeModifierFlags: CGEventFlags = []
    private var lastTapTime: TimeInterval = 0
    private var active = false

    private let holdThreshold: TimeInterval = 0.15
    private let doubleTapInterval: TimeInterval = 0.35
    private let timerQueue = DispatchQueue(label: "vaakya.hotkey.timer")

    init(keyCode: Int, doubleTapEnabled: Bool) {
        self.keyCode = CGKeyCode(keyCode)
        self.doubleTapEnabled = doubleTapEnabled
    }

    /// Thread-safe handler registration (written on MainActor, read on the tap queue).
    var onGesture: ((Gesture) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return onGestureHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            onGestureHandler = newValue
        }
    }

    static func preflight() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// True when the event tap was created (i.e., Input Monitoring is granted).
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard eventTap == nil else { return }
        let mask = CGEventMask(
            1 << CGEventType.keyDown.rawValue
            | 1 << CGEventType.keyUp.rawValue
            | 1 << CGEventType.flagsChanged.rawValue // modifier-only keys (Left Option) fire THIS, never keyDown/keyUp
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly, // observe-only: we never swallow the modifier (plan §6)
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr) else {
            return
        }
        eventTap = tap
        active = true
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        lock.lock()
        holdTimer?.cancel()
        holdTimer = nil
        active = false
        isHeld = false
        isLatched = false
        ignoreNextKeyUp = false
        suppressHotkeyUntilRelease = false
        activeModifierFlags = []
        lastTapTime = 0 // review fix: stale isHeld/lastTapTime would swallow the first keyDown after a re-arm
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap) // release the tap (and our userInfo ref)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        lock.unlock()
    }

    /// Clears latch bookkeeping when recording ends without another hotkey
    /// press, for example when the empty-audio safety fallback fires.
    func cancelLatch() {
        lock.lock()
        isLatched = false
        ignoreNextKeyUp = false
        lastTapTime = 0
        lock.unlock()
    }

    // MARK: - event handling (any thread; state serialized under `lock`)

    /// Copy the handler under the lock and invoke it outside — the owner's
    /// handler must never run while we hold the non-reentrant lock (security
    /// review: prevents a re-entrant start()/stop() deadlock).
    private func deliver(_ gesture: Gesture) {
        lock.lock()
        let handler = onGestureHandler
        lock.unlock()
        handler?(gesture)
    }

    private func handle(event: CGEvent) {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Modifier hotkeys need every flagsChanged event, not only their own.
        // This lets Option followed by Command cancel before the hold timer fires.
        if event.type == .flagsChanged, let hotkeyFlag = Self.modifierFlag(for: keyCode) {
            handleModifierFlagsChanged(event: event,
                                       eventKeyCode: eventKeyCode,
                                       hotkeyFlag: hotkeyFlag)
            return
        }

        guard eventKeyCode == keyCode else { return }
        lock.lock()
        defer { lock.unlock() }
        switch event.type {
        case .keyDown:
            handleKeyDown()
        case .keyUp:
            handleKeyUp()
        default:
            break
        }
    }

    private func handleModifierFlagsChanged(event: CGEvent,
                                            eventKeyCode: CGKeyCode,
                                            hotkeyFlag: CGEventFlags) {
        lock.lock()
        defer { lock.unlock() }

        activeModifierFlags = event.flags.intersection(HotkeyModifierPolicy.activationModifiers)
        let hotkeyIsDown = activeModifierFlags.contains(hotkeyFlag)

        if hotkeyIsDown,
           !HotkeyModifierPolicy.allowsActivation(activeFlags: activeModifierFlags,
                                                   hotkeyFlag: hotkeyFlag) {
            suppressModifiedHotkeyLocked()
            return
        }

        // A different modifier may have been released while Option remains down.
        // A chord that began modified stays suppressed until Option is released.
        guard eventKeyCode == keyCode else { return }

        if hotkeyIsDown {
            guard !suppressHotkeyUntilRelease else { return }
            handleKeyDown()
        } else if suppressHotkeyUntilRelease {
            suppressHotkeyUntilRelease = false
            ignoreNextKeyUp = false
        } else {
            handleKeyUp()
        }
    }

    /// Caller must hold `lock`.
    private func suppressModifiedHotkeyLocked() {
        suppressHotkeyUntilRelease = true
        holdTimer?.cancel()
        holdTimer = nil
        lastTapTime = 0

        guard isHeld else { return }
        isHeld = false
        lock.unlock()
        deliver(.holdEnded)
        lock.lock()
    }

    /// The modifier flag for a modifier key code, or nil for regular keys
    /// (those use the keyDown/keyUp path above).
    private static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand      // R/L Command
        case 56, 60: return .maskShift        // L/R Shift
        case 58, 61: return .maskAlternate    // L/R Option
        case 59, 62: return .maskControl      // L/R Control
        case 63: return .maskSecondaryFn      // Fn
        default: return nil
        }
    }

    private func handleKeyDown() {
        let now = ProcessInfo.processInfo.systemUptime
        if isLatched {
            // The next press after a double-tap is the explicit latch stop.
            // Ignore its matching key-up so it cannot start a new hold cycle.
            isLatched = false
            ignoreNextKeyUp = true
            lock.unlock()
            deliver(.latchEnded)
            lock.lock()
            return
        }
        if doubleTapEnabled, !isHeld, now - lastTapTime < doubleTapInterval {
            // Second tap of a double-tap → latch mode.
            lastTapTime = 0
            isLatched = true
            ignoreNextKeyUp = true
            lock.unlock()
            deliver(.doubleTapBegan)
            lock.lock()
            return
        }
        lastTapTime = now
        if !isHeld {
            startHoldTimerLocked()
        }
    }

    private func handleKeyUp() {
        if ignoreNextKeyUp {
            ignoreNextKeyUp = false
            return
        }
        if let holdTimer {
            holdTimer.cancel()
            self.holdTimer = nil
        }
        let wasHeld = isHeld
        isHeld = false
        lock.unlock()
        deliver(wasHeld ? .holdEnded : .singleTap)
        lock.lock()
    }

    /// Caller must hold `lock`.
    private func startHoldTimerLocked() {
        holdTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + holdThreshold, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var began = false
            self.lock.lock()
            let modifierEligible: Bool
            if let hotkeyFlag = Self.modifierFlag(for: self.keyCode) {
                modifierEligible = HotkeyModifierPolicy.allowsActivation(
                    activeFlags: self.activeModifierFlags,
                    hotkeyFlag: hotkeyFlag)
            } else {
                modifierEligible = true
            }
            if !self.isHeld, !self.suppressHotkeyUntilRelease, modifierEligible {
                self.isHeld = true
                began = true
            }
            self.lock.unlock()
            if began {
                self.deliver(.holdBegan)
            }
        }
        timer.resume()
        holdTimer = timer
    }
}
