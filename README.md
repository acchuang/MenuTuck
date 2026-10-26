# MenuTuck

<p align="center">
  <img src="Resources/AppIcon-1024.png" width="140" height="140" alt="MenuTuck App Icon" />
</p>

<p align="center">
  <strong>Native macOS Menu Bar Icon Manager</strong><br/>
  Hide, reveal, and organize menu bar icons into <em>Visible</em>, <em>Hidden</em>, and <em>Always Hidden</em> sections using native macOS APIs.
</p>

<p align="center">
  <a href="https://github.com/acchuang/MenuTuck/releases/latest/download/MenuTuck.dmg"><strong>⬇ Download MenuTuck.dmg (v0.1.0)</strong></a> ·
  <a href="https://github.com/acchuang/MenuTuck/releases/latest/download/MenuTuck-macOS.zip"><strong>⬇ Download MenuTuck-macOS.zip</strong></a> ·
  <a href="https://github.com/acchuang/MenuTuck/releases"><strong>All Releases</strong></a>
</p>

---

## Download & Install

1. Download [**`MenuTuck.dmg`**](https://github.com/acchuang/MenuTuck/releases/latest/download/MenuTuck.dmg) (or [**`MenuTuck-macOS.zip`**](https://github.com/acchuang/MenuTuck/releases/latest/download/MenuTuck-macOS.zip)) from the [latest GitHub Release](https://github.com/acchuang/MenuTuck/releases/latest).
2. Drag **`MenuTuck.app`** into **`/Applications`**.
3. Clear the macOS quarantine attribute (since the binary uses ad-hoc code signing) and launch:
   ```bash
   xattr -cr /Applications/MenuTuck.app
   open /Applications/MenuTuck.app
   ```
4. Grant **Accessibility** access when prompted (**System Settings → Privacy & Security → Accessibility**) so MenuTuck can detect live `⌘`-drags across dividers and trigger menu bar items.

---

## Features

- **Three Menu Bar Sections (`Visible`, `Hidden`, `Always Hidden`)**:
  - **`|‹` / `|›` (Hidden Divider & Toggle)**: Sits between the **Hidden** section (to its left) and the **Visible** section (to its right).
  - **`‖` (Always-Hidden Divider)**: Sits between the **Always Hidden** section (to its left) and the **Hidden** section (to its right).
- **Native In-Place Hiding on macOS 26/27 (`MenuBarAgent`)**:
  - Uses `MenuBarClientCore` (`MBAssessmentModeAssertion`) on macOS 26/27 to hide and restore third-party menu bar icons in place (`<15 ms`) with zero Screen Recording permissions.
  - Falls back to expandable `NSStatusItem` spacers (`10,000 pt`) on macOS 14–15.
- **Two Ways to Organize Icons**:
  - **In the Menu Bar**: Hold `⌘` and drag any icon to the left of `|‹` / `|›` to hide it, or to the left of `‖` to always hide it.
  - **In Settings (`Menu Bar Items` tab)**: Assign any running menu bar app to **Visible**, **Hidden**, or **Always Hidden** with the section picker, or click **Click** to trigger its menu bar item remotely.
- **Quick Controls**:
  - **Left-click `|‹` / `|›`**: Toggle Hidden icons.
  - **Option-click (`⌥`-click) `|‹` / `|›` or click `‖`**: Show All icons (including Always Hidden).
  - **Right-click `|‹` / `|›`**: Open the quick menu (*Show/Hide Icons*, *Show All Icons*, *Settings…*, *Quit*).
  - **Global Shortcut (`⌃⌥M`)**: Toggle Hidden icons from anywhere.
- **Auto-Rehide & Launch at Login**:
  - Automatically collapses hidden icons after a configurable delay (`3–60 s`) or when clicking outside the menu bar.
  - Native `SMAppService` Launch at Login support.

---

## Architecture

| File | Responsibility |
| --- | --- |
| [`Sources/MenuTuck/main.swift`](Sources/MenuTuck/main.swift) | App entry point (`NSApplication.ActivationPolicy.accessory`). |
| [`Sources/MenuTuck/AppDelegate.swift`](Sources/MenuTuck/AppDelegate.swift) | App lifecycle, startup scan, and Settings window routing. |
| [`Sources/MenuTuck/SectionController.swift`](Sources/MenuTuck/SectionController.swift) | Manages the `|‹`/`|›` and `‖` status items, self-targeted `AXUIElement` frame tracking, hotkeys, and auto-rehide timers. |
| [`Sources/MenuTuck/MenuBarHider.swift`](Sources/MenuTuck/MenuBarHider.swift) | Bridges `MenuBarClientCore` (`MBAssessmentModeAssertion` & `MBAssessmentModeConfiguration`) for native in-place icon hiding. |
| [`Sources/MenuTuck/MenuBarScanner.swift`](Sources/MenuTuck/MenuBarScanner.swift) | Parallel `AXUIElement` (`kAXExtrasMenuBarAttribute`) scanner and action dispatcher. |
| [`Sources/MenuTuck/ItemsModel.swift`](Sources/MenuTuck/ItemsModel.swift) | Classifies items relative to `|›` and `‖` and reconciles live `⌘`-drags with Settings overrides. |
| [`Sources/MenuTuck/Preferences.swift`](Sources/MenuTuck/Preferences.swift) | `UserDefaults`-backed observable settings and per-app section overrides. |
| [`Sources/MenuTuck/SettingsView.swift`](Sources/MenuTuck/SettingsView.swift) | SwiftUI Settings interface (*Menu Bar Items* and *General* tabs). |

---

## Build from Source

Requirements: macOS 14.0+ and Xcode / Swift 5.10+.

```bash
git clone https://github.com/acchuang/MenuTuck.git
cd MenuTuck

# Build release app bundle and install to /Applications/MenuTuck.app
./scripts/build-app.sh release

# Optional: regenerate Resources/AppIcon.icns from CoreGraphics script
swift scripts/generate-icon.swift
```

## License

MIT © acchuang
