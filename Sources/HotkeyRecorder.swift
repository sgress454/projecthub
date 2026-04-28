import AppKit
import CoreGraphics
import ProjectHubKit

/// One-shot recorder that captures the next modifier-bearing keystroke
/// anywhere on the system, even when another app has already registered the
/// chord as a global hotkey (which is the common case here — iTerm2's hotkey
/// window IS bound to the chord we're trying to record).
///
/// Implementation: a HID-level `CGEventTap` with `.headInsertEventTap`
/// placement. That position fires before WindowServer routes the event to
/// the registered hotkey owner, so returning nil from the callback consumes
/// the event before iTerm sees it. Without this, `NSEvent.addLocalMonitor*`
/// never receives the keystroke at all because iTerm intercepts it first.
///
/// Tap teardown is automatic on capture, on Esc, or on `cancel()`. The
/// recorder must be `start()`ed on the main thread; callbacks fire on the
/// main thread.
final class HotkeyRecorder {
    enum StartResult {
        case started
        case notTrusted
        case failedToCreateTap
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let onCapture: (RecordedShortcut) -> Void
    private let onCancel: () -> Void

    init(onCapture: @escaping (RecordedShortcut) -> Void, onCancel: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    deinit { teardown() }

    @discardableResult
    func start() -> StartResult {
        guard tap == nil else { return .started }
        guard SpaceSwitcher.hasAccessibility() else { return .notTrusted }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyRecorderTapCallback,
            userInfo: opaqueSelf
        ) else {
            return .failedToCreateTap
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return .started
    }

    func cancel() {
        teardown()
        onCancel()
    }

    private func teardown() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The tap can be disabled by macOS for "user input timeout" or other
        // reasons — re-enable so we don't silently die.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Esc cancels the recording without storing anything.
        if keyCode == 0x35 {
            DispatchQueue.main.async { [weak self] in self?.cancel() }
            return nil
        }

        let nsFlags = Self.nsFlags(from: event.flags)
        let interesting: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard !nsFlags.intersection(interesting).isEmpty else {
            // No modifier — pass through. The user is just typing.
            return Unmanaged.passUnretained(event)
        }

        let captured = RecordedShortcut(
            keyCode: keyCode,
            modifierFlags: nsFlags.rawValue
        )
        DispatchQueue.main.async { [weak self] in
            self?.teardown()
            self?.onCapture(captured)
        }
        return nil
    }

    /// Translate `CGEventFlags` (what the tap gives us) into the
    /// `NSEvent.ModifierFlags` raw value we persist in `RecordedShortcut`.
    private static func nsFlags(from cg: CGEventFlags) -> NSEvent.ModifierFlags {
        var ns: NSEvent.ModifierFlags = []
        if cg.contains(.maskCommand)    { ns.insert(.command) }
        if cg.contains(.maskControl)    { ns.insert(.control) }
        if cg.contains(.maskAlternate)  { ns.insert(.option) }
        if cg.contains(.maskShift)      { ns.insert(.shift) }
        if cg.contains(.maskAlphaShift) { ns.insert(.capsLock) }
        if cg.contains(.maskSecondaryFn){ ns.insert(.function) }
        return ns
    }
}

/// `@convention(c)` callback — no captured state, threads the recorder
/// reference through `userInfo`.
private func hotkeyRecorderTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let recorder = Unmanaged<HotkeyRecorder>.fromOpaque(userInfo).takeUnretainedValue()
    return recorder.handleTapEvent(type: type, event: event)
}
