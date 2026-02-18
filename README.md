# SwissKnife — macOS Menu Bar Toolbox

A lightweight menu bar app for macOS that bundles multiple tools under a single icon. Built with SwiftUI, runs entirely on-device.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)

## Tools

### BG Remover
Remove image backgrounds using Apple's native Vision AI framework. No internet required.
- Paste from clipboard (⌘V), drag & drop, or file picker
- Uses `VNGenerateForegroundInstanceMaskRequest` (macOS 14+)
- Copy result or save as PNG with transparency

### World Clocks
View multiple time zones at a glance with a built-in time converter.
- Add cities or custom GMT offsets
- Live updating clocks
- Convert times between your saved zones

## Requirements

- **macOS 14.0 (Sonoma)** or later
- Xcode 15+

## Installation

### Build from Xcode
1. Open `SwissKnife.xcodeproj` in Xcode
2. Select your signing team (or sign to run locally)
3. Build & Run (⌘R)
4. The app appears in your menu bar

### Build from Terminal
```bash
xcodebuild -project SwissKnife.xcodeproj -scheme SwissKnife -configuration Release build
```

## Adding New Tools

1. Add a case to the `Tool` enum in `MainView.swift`
2. Create your tool's SwiftUI view
3. Add a preview widget for the home screen card
4. Done — the home grid and search pick it up automatically

## Bundle ID

`com.damascuss.SwissKnife`
