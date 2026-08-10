import AppKit
import CoreGraphics
import Foundation
import VaakyaCore

/// Observe only Left Option modifier transitions. No ordinary key events are
/// subscribed to, recorded, or retained.
final class HotkeyMonitor: @unchecked Sendable {
    enum Gesture {
        case began
        case ended
    }

    private let leftOptionKeyCode = CGKeyCode(58)
    private let holdThreshold: TimeInterval = 0.15
    private let lock = NSLock()
    private let timerQueue = DispatchQueue(label: "vaakya.work-safe.hotkey")
    private var handler: ((Gesture) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdTimer: DispatchSourceTimer?
    private var optionPressed = false
    private var recording = false
    private var active = false

    var onGesture: ((Gesture) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return handler
        }
        set {
            lock.lock()
            handler = newValue
            lock.unlock()
        }
    }

    static func preflight() -> Bool {
        CGPreflightListenEventAccess()
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                Unmanaged<HotkeyMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                    .handle(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: pointer
        ) else {
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
        optionPressed = false
        recording = false
        active = false
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        lock.unlock()
    }

    private func handle(_ event: CGEvent) {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags.intersection(HotkeyModifierPolicy.activationModifiers)
        let leftOptionDown = eventKeyCode == leftOptionKeyCode
            && modifiers.contains(.maskAlternate)
            && HotkeyModifierPolicy.allowsActivation(
                activeFlags: modifiers,
                hotkeyFlag: .maskAlternate
            )

        var gesture: Gesture?
        var callback: ((Gesture) -> Void)?

        lock.lock()
        if leftOptionDown, !optionPressed {
            optionPressed = true
            scheduleHoldTimerLocked()
        } else if optionPressed,
                  (!modifiers.contains(.maskAlternate) || modifiers != .maskAlternate) {
            optionPressed = false
            holdTimer?.cancel()
            holdTimer = nil
            if recording {
                recording = false
                gesture = .ended
                callback = handler
            }
        }
        lock.unlock()

        if let gesture {
            callback?(gesture)
        }
    }

    /// Caller holds `lock`.
    private func scheduleHoldTimerLocked() {
        holdTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + holdThreshold)
        timer.setEventHandler { [weak self] in
            self?.holdThresholdReached()
        }
        holdTimer = timer
        timer.resume()
    }

    private func holdThresholdReached() {
        lock.lock()
        guard optionPressed, !recording else {
            lock.unlock()
            return
        }
        recording = true
        holdTimer = nil
        let callback = handler
        lock.unlock()
        callback?(.began)
    }
}
