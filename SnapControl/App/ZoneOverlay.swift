import AppKit

/// Transparent surface over a display that shows the zones; the zone under the pointer is highlighted.
/// Accepts no mouse events, never becomes active and appears on all Spaces (also next to full-screen apps).
/// A fresh window per showing, discarded on hiding: a permanently reused window lost individual Spaces
/// after a while (observed via CGSCopySpacesForWindows: only 44 and 4 instead of 4, 5, 44) and stayed there
/// invisible although `canJoinAllSpaces` was set. Within one drag the window moves along
/// when the display changes; drawing happens only when the zone or display changes.
@MainActor
final class ZoneOverlay {
    private var panel: NSPanel?
    private var view = ZoneView()
    private var shownScreen: CGRect?
    private var shownZones: [CGRect] = []
    private var shownIndex: Int?

    func show(on screen: NSScreen, zones: [CGRect], highlighted: Int) {
        let panel = panel ?? makePanel()
        if shownScreen != screen.frame {
            shownScreen = screen.frame
            panel.setFrame(screen.frame, display: false)
        }
        if shownZones != zones || shownIndex != highlighted {
            shownZones = zones
            shownIndex = highlighted
            view.origin = screen.frame.origin
            view.zones = zones
            view.highlighted = highlighted
            view.needsDisplay = true
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        shownScreen = nil
        shownZones = []
        shownIndex = nil
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        view = ZoneView()
        p.contentView = view
        panel = p
        return p
    }
}

/// Draws the zones in the accent color: all tinted with a border, the target zone strongly highlighted.
final class ZoneView: NSView {
    var origin: CGPoint = .zero
    var zones: [CGRect] = []
    var highlighted: Int?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        for (i, zone) in zones.enumerated() {
            let r = zone.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
            let hot = i == highlighted
            accent.withAlphaComponent(hot ? 0.38 : 0.12).setFill()
            path.fill()
            accent.withAlphaComponent(hot ? 1 : 0.5).setStroke()
            path.lineWidth = hot ? 3 : 1
            path.stroke()
        }
    }
}
