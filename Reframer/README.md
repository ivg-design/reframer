# Reframer

A transparent video overlay app for macOS that floats above all windows.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Overview

Reframer lets you overlay reference videos on your screen while working in other applications. Perfect for:

- **Animation reference** — Trace over video frames while drawing
- **Motion design** — Match timing with real footage
- **UI/UX work** — Compare designs with video prototypes
- **Learning** — Follow along with video tutorials

The app window is completely transparent and frameless, showing only the video content. Controls appear on hover or can be locked for uninterrupted work.

## Features

- **Transparent overlay** — No window chrome, just pure video
- **Always on top** — Stays visible above all other windows
- **Persistent settings** — Remembers opacity, volume, and window position
- **Frame-accurate navigation** — Step through videos frame by frame
- **Zoom and pan** — Inspect details at any scale (Ctrl+drag to pan, Shift+scroll to zoom)
- **Adjustable opacity** — Blend with your workspace
- **Lock mode** — Click through the video to interact with apps below
- **Keyboard shortcuts** — Full control without touching the mouse
- **Edge glow indicators** — Subtle visual hints for window resize handles
- **YouTube links** — Paste a YouTube URL (long-press Open)

## Supported Formats

MP4, MOV, ProRes, H.264, H.265, AV1, WebM, MKV, AVI (WebM/MKV require libmpv)

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open video | ⌘O |
| Play/Pause | Space |
| Step forward | → or Page Down |
| Step backward | ← or Page Up |
| Pan | Ctrl+drag or Arrow keys |
| Zoom in/out | Shift+scroll |
| Fine zoom | ⌘+Shift+scroll |
| Reset view | R |
| Reset zoom to 100% | 0 |
| Toggle lock | L |
| Toggle help | H or ? |

## Requirements

- macOS 14.0 (Sonoma) or later

## Installation

1. Download the latest release from [Releases](https://github.com/ivg-design/reframer/releases)
2. Move Reframer.app to your Applications folder
3. Launch and drop a video file onto the window

## Building from Source

```bash
git clone https://github.com/ivg-design/reframer.git
cd reframer/Reframer
open Reframer.xcodeproj
```

Build with Xcode 15 or later.

## License

MIT License - see [LICENSE](LICENSE) for details.
