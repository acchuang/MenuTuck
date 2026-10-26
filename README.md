# MenuTuck

<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" height="128" alt="MenuTuck App Icon" />
</p>

A lightweight, native macOS menu bar icon manager built with `AppKit`, `SwiftUI`, `MenuBarClientCore` (`MBAssessmentModeAssertion`), and `ApplicationServices` (`AXUIElement`).

## Features

- **Three Menu Bar Sections**: Organize status items into **Visible**, **Hidden**, and **Always Hidden** sections separated by draggable menu bar dividers (`‖` and `|‹` / `|›`).
- **Native In-Place Hiding on macOS 26/27 (`MenuBarAgent`)**: Uses `MenuBarClientCore` (`MBAssessmentModeAssertion`) to hide and reveal third-party menu bar icons in place without screen recording permissions or `10,000 pt` window clipping bugs.
- **Drag-to-Hide & Settings Control**:
  - Hold `⌘` and drag any menu bar icon to the left of `|‹` / `|›` to hide it, or to the left of `‖` to always hide it.
  - Or assign any app to **Visible**, **Hidden**, or **Always Hidden** in **Settings → Menu Bar Items**.
  - Trigger any menu bar item directly from the Settings window via **Click**.
- **Quick Controls**:
  - **Left-click** `|‹` / `|›` to toggle Hidden icons.
  - **Option-click (`⌥`-click)** `|‹` / `|›` (or click `‖`) to reveal All icons (including Always Hidden).
  - **Right-click** `|‹` / `|›` for the quick menu.
  - **Global Shortcut (`⌃⌥M`)** to toggle Hidden icons from anywhere.
- **Auto-Rehide**: Automatically collapses hidden icons after a configurable delay (3–60 s) or when clicking outside the menu bar.

## Build & Install

```bash
# Build release bundle and install to /Applications/MenuTuck.app
./scripts/build-app.sh

# Regenerate Resources/AppIcon.icns and Resources/AppIcon-1024.png
swift scripts/generate-icon.swift

# Launch
open /Applications/MenuTuck.app
```
