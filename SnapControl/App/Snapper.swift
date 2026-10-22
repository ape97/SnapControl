import AppKit
import ApplicationServices
import os

/// Snapping: when a window is dragged while the key (default ⌃) is held, `ZoneOverlay` shows the zones of the
/// active grid; when the mouse is released, the window gets exactly the size of the zone under the pointer.
///
/// Performance: without an active grid there is no monitor (0 % CPU). With a grid only global mouse/key monitors run;
/// at most one accessibility query for the window per drag, then a position comparison at most every 50 ms
/// and only while the key is held. The overlay is redrawn only when the zone changes.
@MainActor
final class Snapper {
    static let shared = Snapper()

    private var monitors: [Any] = []
    private var grid: GridSet?
    private var key: NSEvent.ModifierFlags = .control
    private let overlay = ZoneOverlay()
    private let log = Logger(subsystem: "io.github.ape97.snapcontrol", category: "snap")

    // State of the current drag
    private var downPoint: CGPoint?
    private var looked = false
    private var window: AXUIElement?
    private var startPosition: CGPoint?
    private var moving = false
    private var lastCheck: TimeInterval = 0
    private var target: CGRect?

    private init() {}

    var isRunning: Bool { !monitors.isEmpty }

    func start(grid: GridSet, key: SnapKey) {
        self.grid = grid
        self.key = key.flag
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { Snapper.shared.handle(event) }
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        grid = nil
        reset()
    }

    // MARK: Events

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            reset()
            downPoint = NSEvent.mouseLocation
        case .leftMouseDragged, .flagsChanged:
            guard downPoint != nil, NSEvent.pressedMouseButtons & 1 == 1 else { return }
            if !looked { lookUpWindow() }
            update(held: event.modifierFlags.contains(key))
        case .leftMouseUp:
            let snap = moving && event.modifierFlags.contains(key) ? target : nil
            let window = window
            reset()
            if let snap, let window {
                // Wait briefly until the system has finished the drag – otherwise it resets the position.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    MainActor.assumeIsolated { Snapper.shared.place(window, in: snap) }
                }
            }
        default:
            break
        }
    }

    /// Once per drag: the window under the point where the mouse was pressed, with its start position.
    private func lookUpWindow() {
        looked = true
        guard let downPoint, let w = WindowAX.window(at: downPoint) else { return }
        window = w
        startPosition = WindowAX.position(of: w)
    }

    private func update(held: Bool) {
        guard held, let grid else { return hideOverlay() }
        if !moving {
            // Only once the window really moves is it a window drag (not selecting text or the like).
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastCheck > 0.05, let window, let startPosition else { return }
            lastCheck = now
            guard let p = WindowAX.position(of: window), p != startPosition else { return }
            moving = true
        }
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return }
        let frames = Zones.frames(grid, in: screen.visibleFrame)
        guard let i = Zones.index(of: point, in: frames) else { return }
        target = frames[i]
        overlay.show(on: screen, zones: frames, highlighted: i)
    }

    private func hideOverlay() {
        target = nil
        overlay.hide()
    }

    private func reset() {
        downPoint = nil
        looked = false
        window = nil
        startPosition = nil
        moving = false
        lastCheck = 0
        hideOverlay()
    }

    private func place(_ window: AXUIElement, in rect: CGRect) {
        let primary = NSScreen.screens.first?.frame.maxY ?? 0
        if !WindowAX.setFrame(window, Zones.axRect(rect, primaryHeight: primary)) {
            log.error("Could not set the window")
        }
    }
}

/// Window access via accessibility (needs the permission under Privacy → Accessibility).
enum WindowAX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system permission dialog once (only if not yet granted).
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Window at a point (Cocoa coordinates). The app's own windows don't count.
    static func window(at point: CGPoint) -> AXUIElement? {
        let primary = NSScreen.screens.first?.frame.maxY ?? 0
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(primary - point.y), &element) == .success,
              let element else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid() else { return nil }
        if role(of: element) == kAXWindowRole { return element }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(of window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    /// Size → position → size: some apps limit the size at the old location (screen edge); after the move
    /// it fits. "AXEnhancedUserInterface" (on if VoiceOver or similar was running) makes apps animate and discard
    /// values – switched off for the duration of the set.
    @discardableResult
    static func setFrame(_ window: AXUIElement, _ rect: CGRect) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        let enhanced = "AXEnhancedUserInterface" as CFString
        var flag: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(app, enhanced, &flag) == .success && (flag as? Bool) == true
        if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanFalse) }
        defer { if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanTrue) } }

        var size = rect.size, origin = rect.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return false }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue) == .success
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return moved
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
