# BG Remover — macOS Menu Bar App

A lightweight menu bar app for macOS that removes image backgrounds using Apple's native Vision AI framework. No internet connection required, everything runs locally on your Mac.

![Menu Bar App](https://img.shields.io/badge/macOS-14.0%2B-blue)

## Features

- 🖼️ **Paste from clipboard** (⌘V) — screenshot something, paste it, done
- 📂 **Drag & drop** images directly into the popover
- 📁 **File picker** for choosing images from disk
- 🤖 **On-device AI** — uses Apple Vision `VNGenerateForegroundInstanceMaskRequest` (macOS 14+)
- 📋 **Copy result** to clipboard as PNG with transparency
- 💾 **Save as PNG** with transparent background
- 🎨 Checkerboard preview to see transparency
- ⚡ Fast — runs entirely on your Mac's Neural Engine

## Requirements

- **macOS 14.0 (Sonoma)** or later (for best results with Vision framework)
- Xcode 15+

## Installation

### Option 1: Build from Xcode
1. Open `BGRemover.xcodeproj` in Xcode
2. Select your signing team (or sign to run locally)
3. Build & Run (⌘R)
4. The app appears in your menu bar with a person-crop icon

### Option 2: Build from Terminal
```bash
cd bgremover
xcodebuild -project BGRemover.xcodeproj -scheme BGRemover -configuration Release build
```

## Usage

1. Click the icon in the menu bar — a popover opens (like your Time Converter)
2. Either:
   - Press **⌘V** to paste an image from clipboard
   - **Drag & drop** an image into the window
   - Click **"Choose File…"** to pick from Finder
3. Wait ~1-3 seconds for background removal
4. Toggle between **Original** / **No Background** views
5. Click **Copy** to copy the result (PNG with transparency) to clipboard
6. Or click **Save PNG** to save to disk

## How it Works

Uses Apple's `VNGenerateForegroundInstanceMaskRequest` from the Vision framework, which runs the same AI model that powers the "Lift Subject" feature in macOS Photos and Preview. The neural network runs entirely on-device using the Apple Neural Engine — no data leaves your Mac.

For macOS < 14, it falls back to `VNGenerateAttentionBasedSaliencyImageRequest` which gives rougher results.

## Bundle ID

`com.damascuss.BGRemover`
