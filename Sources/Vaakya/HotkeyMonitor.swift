import AppKit
import CoreGraphics
import Foundation

/// CGEvent session event tap for the dictation hotkey (plan §6):
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
        guard Int(event.getIntegerValueField(.keyboardEventKeycode)) == Int(keyCode) else { return }
        lock.lock()
        defer { lock.unlock() }
        switch event.type {
        case .keyDown:
            handleKeyDown()
        case .keyUp:
            handleKeyUp()
        case .flagsChanged:
            // Modifier-only keys (the default Left Option, keyCode 58) deliver
            // ONLY flagsChanged — without this branch the hotkey can never fire
            // (review finding #1; explains R7's "hold-Option did nothing").
            // Press = the modifier's flag became set; release = cleared.
            // Caveat: the flag reflects either key of that modifier type, so
            // holding both Option keys confuses press/release — accepted for a
            // personal app; documented in plan §6.
            guard let flag = Self.modifierFlag(for: keyCode) else { break }
            if event.flags.contains(flag) {
                handleKeyDown()
            } else {
                handleKeyUp()
            }
        default:
            break
        }
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
            if !self.isHeld {
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
