# Platform state

The macOS/Xcode version Snap Control was last fully tested against (`scripts/check.sh` green, deployed).
`scripts/status.sh` compares the last `tested:` line with the running system.
Append new lines at the bottom and keep the format exactly (the "Platform now" value from `status.sh` + ` date=YYYY-MM-DD`).

## Dependencies on the system (an update can break these)
- **MenuBarExtra (.window)** and window notifications used to detect the menu closing (`App/AppModel.swift`).
- **SMAppService** (login item) – `scripts/status.sh` checks it via `sfltool dumpbtm`.
- **Private AppKit methods** used by the performance test (`App/StructureTest.swift`): `_updateStructuralRegionsOnNextDisplayCycle`,
  `_setTrackingAreasDirty:` – test only, not the app.
- **Accessibility API** (`AXUIElementCopyElementAtPosition`, `kAXPosition`/`kAXSize`) and global `NSEvent` monitors
  (`App/Snapper.swift`); the overlay is an `NSPanel` on all Spaces (`App/ZoneOverlay.swift`).
- **macOS tiling**: the keys `EnableTilingByEdgeDrag`, `EnableTopTilingByEdgeDrag`, `EnableTilingOptionAccelerator`
  in the `com.apple.WindowManager` domain (`App/MacTiling.swift`). If Apple renames them, disabling no longer works.
  Restart goes through the launchd service `gui/<uid>/com.apple.WindowManager.agent` (KeepAlive; fallback: kill the process),
  start time via `sysctl` `KERN_PROC_PID`. If WindowManager reads the values live on some day, the restart becomes unnecessary.
- **Signing**: builds are ad-hoc signed by default. If you sign with your own certificate via `Config/Local.xcconfig`, it expires; `scripts/status.sh` shows when, then renew it in Xcode.
- **GitHub releases API** (`App/UpdateCheck.swift`), only while Check for Updates is on: `GET api.github.com/repos/ape97/SnapControl/releases/latest`,
  reads `tag_name` and `html_url`, ignores drafts and pre-releases. If GitHub changes this, only the update notice stops working.

tested: macOS=27.0.1 (26A434) Xcode=27.0 SDK=27.0 date=2026-10-18
