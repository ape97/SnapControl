import AppKit
import Observation
import os

/// Central app state.
///
/// Performance pattern: if the app needs a tick, use exactly one `Timer` (with `tolerance`, run-loop mode `.common`).
/// Sampled values go into `@ObservationIgnored` buffers and are handed to observed properties only while the menu is
/// open – otherwise SwiftUI re-evaluates the invisible menu on every tick.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// SF Symbol in the menu bar (and in the app icon); filled while a grid is active.
    static let menuBarSymbol = "rectangle.split.2x2"
    static let menuBarSymbolActive = "rectangle.split.2x2.fill"

    /// Saved sets (in menu order).
    private(set) var sets: [GridSet]
    /// Active grid (a saved set or a custom, unsaved one); nil = off.
    private(set) var active: GridSet?
    private(set) var snapKey: SnapKey
    /// Accessibility permission granted – without it, other apps' windows cannot be moved.
    private(set) var isTrusted = WindowAX.isTrusted

    /// Snapshots, self-test and performance test work on their own storage, never on the user's list.
    @ObservationIgnored let store: GridStore
    /// macOS's own tiling: off while a grid is active (never in test runs).
    @ObservationIgnored private(set) lazy var tiling = MacTiling(store: store)

    /// Incremented once the menu window has closed (resets sub-pages and lists).
    private(set) var menuGeneration = 0
    private(set) var isMenuOpen = false

    @ObservationIgnored private var closeChecks: Set<ObjectIdentifier> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Logout/shutdown in progress: only write the macOS values back, don't restart WindowManager.
    @ObservationIgnored private var poweringOff = false

    private init() {
        let defaults = Runtime.headless ? AppModel.scratchDefaults() : .standard
        store = GridStore(defaults: defaults)
        sets = store.loadSets()
        active = store.loadActive()
        snapKey = store.key
        if !Runtime.headless {
            observeMenu()
            observeTrust()
            restartSnapper()
            // Hand macOS tiling back on quit; switch it off again on the next launch with an active grid.
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppModel.shared.tiling.restore(reload: !AppModel.shared.poweringOff) }
            })
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppModel.shared.poweringOff = true }
            })
        }
    }

    static func scratchDefaults() -> UserDefaults {
        let name = "io.github.ape97.snapcontrol.test"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: Grids

    /// Activates a grid; if exactly this one is already active, it is switched off.
    func toggle(_ grid: GridSet) {
        if active?.id == grid.id { deactivate() } else { activate(grid) }
    }

    func activate(_ grid: GridSet) {
        let grid = grid.clamped
        active = grid
        store.save(active: grid)
        store.save(last: grid)
        guard !Runtime.headless else { return }
        if !WindowAX.isTrusted { WindowAX.requestTrust() }
        restartSnapper()
    }

    /// Set up snapping again with the current grid and key; macOS tiling is off while a grid is active.
    private func restartSnapper() {
        guard !Runtime.headless else { return }
        Snapper.shared.stop()
        if let active {
            tiling.disable()
            Snapper.shared.start(grid: active, key: snapKey)
        } else {
            tiling.restore()
        }
    }

    func deactivate() {
        active = nil
        store.save(active: nil)
        restartSnapper()
    }

    /// Toggle at the top: on = last used grid (otherwise the first set), off = no grid.
    func setEnabled(_ on: Bool) {
        if !on { return deactivate() }
        let last = store.loadLast()
        // A saved set in its current version; don't revive a deleted one, but do revive a custom grid.
        if let last, let saved = sets.first(where: { $0.id == last.id }) {
            activate(saved)
        } else if let last, last.name == GridSet.customName {
            activate(last)
        } else if let first = sets.first {
            activate(first)
        } else {
            activate(GridSet(name: GridSet.customName, columns: 2, rows: 2))
        }
    }

    /// Appends a new set or replaces an existing one (same ID). If it is the active grid, the new version applies immediately.
    func save(_ grid: GridSet) {
        let grid = grid.clamped
        if let i = sets.firstIndex(where: { $0.id == grid.id }) { sets[i] = grid } else { sets.append(grid) }
        store.save(sets: sets)
        if active?.id == grid.id { activate(grid) }
    }

    /// Change the order in the list (Settings, up/down arrows).
    func move(_ grid: GridSet, by offset: Int) {
        guard let i = sets.firstIndex(where: { $0.id == grid.id }), sets.indices.contains(i + offset) else { return }
        sets.swapAt(i, i + offset)
        store.save(sets: sets)
    }

    func delete(_ grid: GridSet) {
        sets.removeAll { $0.id == grid.id }
        store.save(sets: sets)
        if active?.id == grid.id { deactivate() }
    }

    func setSnapKey(_ key: SnapKey) {
        snapKey = key
        store.key = key
        restartSnapper()
    }

    func requestTrust() {
        WindowAX.requestTrust()
        WindowAX.openSettings()
    }

    /// Permission changed: macOS announces it system-wide ("com.apple.accessibility.api"), slightly delayed.
    private func observeTrust() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { AppModel.shared.refreshTrust() }
            }
        })
    }

    private func refreshTrust() {
        let trusted = WindowAX.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
    }

    // MARK: Menu open / closed

    private func menuOpened() {
        guard !isMenuOpen else { return }
        isMenuOpen = true
        refreshTrust()
    }

    private func menuClosed() {
        isMenuOpen = false
        menuGeneration += 1
    }

    /// Opened = the menu window becomes key; closed = the window is no longer visible
    /// (a mere loss of focus from a context menu or tooltip does not count).
    private func observeMenu() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.menuOpened() }
        })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { AppModel.shared.awaitClose(window) }
        })
    }

    private func awaitClose(_ window: NSWindow) {
        guard closeChecks.insert(ObjectIdentifier(window)).inserted else { return }
        func check() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak window] in
                MainActor.assumeIsolated {
                    let model = AppModel.shared
                    guard let window, !window.isKeyWindow else {
                        if let window { model.closeChecks.remove(ObjectIdentifier(window)) }
                        return
                    }
                    if window.isVisible { return check() }
                    model.closeChecks.remove(ObjectIdentifier(window))
                    // Measuring aid: scripts/measure-menu.sh ends on this line.
                    Logger(subsystem: "io.github.ape97.snapcontrol", category: "menu").notice("Menu closed")
                    model.menuClosed()
                }
            }
        }
        check()
    }

    // MARK: Testing

    /// For snapshots and the performance test: set up state as if the menu had been open for a few seconds.
    func prepareSnapshot() {
        // Show a custom split in the list (in memory only, not saved)
        if !sets.contains(where: { !$0.isEqual }) {
            sets.append(GridSet(name: "Top Three", columns: 3, rows: 2, split: .rows,
                                strips: [Strip(size: 1, count: 3), Strip(size: 2, count: 3)]))
        }
        // `--grid 2x2` (or `--grid custom`) picks the active grid by its demo target id; 3 × 3 otherwise.
        let grid = Runtime.value(after: "--grid") ?? "3x3"
        active = Runtime.arguments.contains("--off") ? nil : sets.first { $0.demoID == grid }
        isTrusted = !Runtime.arguments.contains("--untrusted")
    }

    /// Performance test: exactly one update as with the menu open (e.g. a tick with new values).
    /// Fill it with its own function once the menu content changes by itself.
    func testStep() {}
}
