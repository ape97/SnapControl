import AppKit

/// The built-in macOS window snapping (drag a window to the edge, ⌥ while dragging) shows its own previews and
/// blocks the zones – especially with ⌥ as the key. While a grid is active, Snap Control switches it off and
/// restores the previous values afterwards. The old values stay saved in the app's own settings
/// until they are written back (even across a crash or restart). Keyboard shortcuts and the Window menu stay.
///
/// WindowManager reads the values only at launch (it ignored changed values while running: with the values off,
/// "Add Tiled Window (hotzoneDrag)" still appeared in the log). So after every real change it is restarted via launchd
/// – like the Dock after `defaults write`. That takes under a second; open windows are left untouched.
struct MacTiling {
    static let realDomain = "com.apple.WindowManager"
    static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag", "EnableTilingOptionAccelerator"]

    /// The real domain `com.apple.WindowManager`; the self-test uses its own.
    var domain = MacTiling.realDomain
    var store: GridStore

    var isDisabled: Bool { store.savedTiling != nil }

    func disable() {
        if store.savedTiling == nil {
            // A missing key = macOS default; it is removed again on restore.
            store.savedTiling = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { k in read(k).map { (k, $0) } })
        }
        let changed = Self.keys.filter { read($0) != false }
        for k in changed { write(k, false) }
        CFPreferencesAppSynchronize(domain as CFString)
        // Without a timestamp (state before 1.3.1) it is unknown whether WindowManager already knows the values.
        if !changed.isEmpty || store.tilingWrittenAt == nil { store.tilingWrittenAt = Date() }
        guard domain == Self.realDomain else { return }
        let written = store.tilingWrittenAt
        DispatchQueue.global(qos: .userInitiated).async { Self.reloadIfStale(written) }
    }

    /// `reload: false` on logout/shutdown: WindowManager restarts anyway afterwards and reads the values.
    func restore(reload: Bool = true) {
        guard let saved = store.savedTiling else { return }
        let changed = Self.keys.filter { read($0) != saved[$0] }
        for k in Self.keys { write(k, saved[k]) }
        CFPreferencesAppSynchronize(domain as CFString)
        store.savedTiling = nil
        if !changed.isEmpty { store.tilingWrittenAt = Date() }
        guard domain == Self.realDomain, reload else { return }
        // Synchronous: a background job would no longer run while the app quits.
        Self.reloadIfStale(store.tilingWrittenAt)
    }

    func read(_ key: String) -> Bool? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
    }

    /// Restart only if WindowManager was started before the last write (also after a crash or hard quit
    /// of the app, which left the values in place without a restart). If it isn't running, it reads them on its next start.
    private static func reloadIfStale(_ written: Date?) {
        guard let written, let start = windowManagerStart(), start < written else { return }
        kickstart()
    }

    private static func windowManagerStart() -> Date? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: realDomain).first?.processIdentifier
        else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let t = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
    }

    /// `kickstart -k` stops the service and starts it again; if that fails, aborting is enough –
    /// launchd restarts it by itself (KeepAlive on unsuccessful exit).
    private static func kickstart() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["kickstart", "-k", "gui/\(getuid())/com.apple.WindowManager.agent"]
        if (try? p.run()) != nil { p.waitUntilExit() }
        if p.terminationReason != .exit || p.terminationStatus != 0 {
            NSRunningApplication.runningApplications(withBundleIdentifier: realDomain).forEach { $0.forceTerminate() }
        }
    }

    private func write(_ key: String, _ value: Bool?) {
        CFPreferencesSetAppValue(key as CFString, value.map { $0 as CFBoolean }, domain as CFString)
    }
}
