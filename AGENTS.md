# AGENTS.md — `MenuTuck`

Native macOS menu bar icon manager (`AppKit` + `SwiftUI`, Swift 5.10+, macOS 14+).
Uses a **Hybrid Divider Architecture** (verified on macOS 27.0.1 and 27.2 only): physical draggable dividers (`‹`/`›`, `|`, `‖`) in the menu bar define section boundaries, while `MenuBarClientCore` (`MBAssessmentModeAssertion`) hides and reveals icons in place.

## Build & Run

```bash
# Build, sign, and install to /Applications/MenuTuck.app (default: release, ad-hoc signed)
./scripts/build-app.sh

# Debug build
./scripts/build-app.sh debug

# Sign with the local self-signed "MenuTuck Dev" cert (keychain: ~/Library/Keychains/menutuck-dev.keychain-db).
# Its designated requirement is stable across rebuilds, so the Accessibility grant survives them.
SIGN_IDENTITY=848A34F423C068B924BE7B3DA75933DEB2A01632 ./scripts/build-app.sh

# Build without touching /Applications (keeps the installed app and its Accessibility grant)
SKIP_INSTALL=1 ./scripts/build-app.sh

# Build build/MenuTuck.dmg and build/MenuTuck-macOS.zip (never installs; prints SHA-256)
./scripts/package.sh

# Run the unit tests (only isOnMenuBar is covered so far)
swift test

# Regenerate Resources/AppIcon.icns and Resources/AppIcon-1024.png
swift scripts/generate-icon.swift

# Launch from /Applications (required so sandboxed MenuBarAgent resolves CFBundleIdentifier)
open /Applications/MenuTuck.app
```

## Architecture

- [`Sources/MenuTuck/main.swift`](Sources/MenuTuck/main.swift) — Entry point (`NSApplication.ActivationPolicy.accessory`).
- [`Sources/MenuTuck/AppDelegate.swift`](Sources/MenuTuck/AppDelegate.swift) — App lifecycle and settings window routing.
- [`Sources/MenuTuck/SectionController.swift`](Sources/MenuTuck/SectionController.swift) — Owns the 2 boundary status items (`toggleItem` `|‹`/`|›` and `alwaysHiddenDivider` `‖`), collapses `‖` to `0 pt` via `NSStatusBarContentView` width-constraint deactivation so `MenuBarAgent` never loses its X position, resolves true macOS 27 screen coordinates via self-targeted `AXUIElementCreateApplication(getpid())`, and watches `ownAXFrames()` every `0.35s` to detect `⌘`-drags across dividers.
- [`Sources/MenuTuck/MenuBarHider.swift`](Sources/MenuTuck/MenuBarHider.swift) — Drives the private `MenuBarClientCore` (`MBAssessmentModeAssertion` + `MBAssessmentModeConfiguration`) to hide and reveal third-party menu bar icons in place. `isSupported` is false unless every selector it calls exists, which selects the spacer fallback. Always invalidates the previous assertion before activating a new one; a failed `activate` is logged and its state is cleared so the next `apply()` retries.
- [`Sources/MenuTuck/MenuBarScanner.swift`](Sources/MenuTuck/MenuBarScanner.swift) — Parallel `AXUIElement` (`kAXExtrasMenuBarAttribute`) scanner.
- [`Sources/MenuTuck/ItemsModel.swift`](Sources/MenuTuck/ItemsModel.swift) — Observable state for scanning, classifying items relative to the `|›` and `‖` dividers, tracking `lastPhysicalSections` so Settings picker overrides and physical `⌘`-drags never overwrite each other, and triggering items.
- [`Sources/MenuTuck/Preferences.swift`](Sources/MenuTuck/Preferences.swift) — `UserDefaults`-backed observable preferences, `sectionOverrides`, and `lastPhysicalSections`.
- [`Sources/MenuTuck/SettingsWindowController.swift`](Sources/MenuTuck/SettingsWindowController.swift) & [`Sources/MenuTuck/SettingsView.swift`](Sources/MenuTuck/SettingsView.swift) — Settings window UI.

## Traps

- **Never read `~/Library/Group Containers/com.apple.MenuBar` from the app bundle**: `sandboxd`, `tccd`, and `cfprefsd` block standalone app bundles from reading `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist` (`kTCCServiceSystemPolicyAppDataDetailed` / `CFPDContainerSource` rejection). Instead, detect `⌘`-drags by monitoring `SectionController.ownAXFrames()` (`getpid()`, zero TCC permissions): because the macOS menu bar is right-anchored at Clock, dragging any icon across `|›` or `‖` shifts `toggle.minX` or `alwaysHidden.minX` by the icon's width.
- **Ad-hoc `cdhash` changes on rebuild invalidate TCC Accessibility (`kTCCServiceAccessibility`)**: Recompiling an ad-hoc signed (`-`) binary changes its `cdhash`, causing `tccd` to log `Failed to match existing code requirement for subject com.acchuang.MenuTuck and service kTCCServiceAccessibility` even while System Settings still displays the toggle as ON. After an ad-hoc rebuild, remove and re-add `MenuTuck` in System Settings -> Privacy & Security -> Accessibility, or run `tccutil reset Accessibility com.acchuang.MenuTuck` (or launch `/Applications/MenuTuck.app/Contents/MacOS/MenuTuck` from a trusted terminal).

- **Always call `invalidate()` on `MBAssessmentModeAssertion` before re-activating**: Calling `activate(withConfiguration:)` a second time on an already-active `MBAssessmentModeAssertion` leaks the previous `VisibilityRestrictionXPCServer` session inside `MenuBarAgent`. Because `MenuBarAgent` takes the union of `allowedBundleIdentifiers` across active sessions, leaked sessions keep previously-visible apps permanently visible. Always call `previousAssertion?.invalidate()` and instantiate a new `MBAssessmentModeAssertion` when changing hidden bundle IDs.
- **macOS 27 `MenuBarAgent` swallows `.leftMouseUp` during `⌘`-drags**: `MenuBarAgent` grabs the pointer during `performDrag`, so `NSEvent` global monitors do not reliably receive `.leftMouseUp`. Instead, monitor `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences` for `TrailingItemPreferredPositions` writes (`Persisting trailing item positions`) and sync before collapsing.
- **macOS 27 `NSStatusBarWindow.frame` is `(0, 0, width, 0)`**: Status items are hosted as FrontBoard scenes inside `MenuBarAgent` (`CGWindowID 7492`), so `item.button?.window?.frame` always returns `origin = (0, 0)`. Always read divider frames via `AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)` (`SectionController.ownAXFrames()`), which works without TCC Accessibility permission.
- **Never set `divider.isVisible = false` to collapse a divider**: On macOS 27, toggling `isVisible = false` -> `true` removes the status item from `MenuBarAgent` and re-inserts it at the far left of all icons, destroying the divider layout. Instead, deactivate the horizontal `NSLayoutConstraint` on `button.window?.contentView` and set `divider.length = 0`.
- **Launch from `/Applications/MenuTuck.app`**: `MenuBarAgent` is sandboxed and cannot read `Contents/Info.plist` inside `~/Project/...`. Installing to `/Applications/MenuTuck.app` (automated by `scripts/build-app.sh`) ensures `MenuBarAgent` resolves `CFBundleIdentifier = "com.acchuang.MenuTuck"` so `MBAssessmentModeAssertion` never hides MenuTuck's own status items.
- **`MenuBarHider` hardcodes `MBSystemItemIdentifier` `0...15` and `4 = keyboard`**: Any system item with an ID above 15 on a newer macOS is not in the allow list and gets hidden. The enum lives only in the dyld shared cache on macOS 27, so it was never read directly; the values are unverified beyond macOS 27.0.1.
- **`outsideClickMonitor` measures against the screen under the click**: `NSEvent.mouseLocation` is global but `NSScreen.main` is the key-window screen, so the monitor picks the screen whose frame contains the click and only falls back to `main`. The band below the bar is `max(36, frame.maxY - visibleFrame.maxY)` (30 pt external, 38 pt notched; the 36 floor covers auto-hide, where `visibleFrame` reports no bar). Verified live on the dev machine (30 pt external + 38 pt notched, aligned top edges): a click 37 pt down on the notched display keeps it expanded, 60 pt collapses. Staggered arrangements are untested.
- **`isOnMenuBar` must accept negative x**: a display left of the primary reports status items at negative x (seen: `‖` at x=-698 on the built-in). The filter only needs to reject parked frames (large y) and unplaced ones at the origin, so it tests `abs(minX) > 5`.
- **Spacer fallback hides only Always Hidden**: `apply()` never lengthens `toggleItem`, and `‖` is left of the Hidden section, so collapsing the `10,000 pt` spacer pushes off only Always Hidden. Reproduced on 27.2 by forcing `isSupported` false. Fixing it needs a third spacer item between `‖` and the toggle.
- **Code Signing**: Never sign with a revoked Apple Development certificate in Keychain. `syspolicyd` / Gatekeeper treats binaries signed with a revoked certificate as malware (`GK evaluateScanResult: 2`) and moves the `.app` bundle to `~/.Trash`. `scripts/build-app.sh` defaults to ad-hoc signing (`-`); for local rebuilds that keep the Accessibility grant, pass `SIGN_IDENTITY` as shown under Build & Run. That cert exists only on the maintainer's machine; check `security find-identity -p codesigning` for it. Released builds stay ad-hoc.
