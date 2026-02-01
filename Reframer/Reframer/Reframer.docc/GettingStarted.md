# Getting Started

Install Reframer and load your first video overlay.

## Overview

Reframer is a single-window app that creates a transparent video overlay on your screen. This guide covers installation, first launch, and basic usage.

## Installation

### From Release

1. Download `Reframer.app` from the releases page
2. Move to `/Applications`
3. Launch the app — it will prompt to move itself if needed

### From Source

```bash
git clone https://github.com/ivg-design/reframer.git
cd reframer/Reframer
open Reframer.xcodeproj
# Build and run (Cmd+R)
```

## First Launch

When you first launch Reframer:

1. A transparent window appears with a **drop zone**
2. The control bar floats at the bottom of the screen
3. Drop a video file or press **⌘O** to open one

## Loading a Video

You can load videos in several ways:

- **Drag and drop** — Drop a video file onto the window
- **Click the drop zone** — Opens a file picker
- **Keyboard** — Press **⌘O** to open a file
- **YouTube link** — Click and hold **Open**, then paste a YouTube URL

Supported formats include MP4, MOV, AVI, MKV, WebM, and ProRes.

## Basic Controls

Once a video is loaded:

| Action | Control |
|--------|---------|
| Play/Pause | **Space** or click the play button |
| Step frames | **← →** arrow keys |
| Zoom | **↑ ↓** arrow keys or **+ -** |
| Pan | Click and drag the video |
| Adjust opacity | Drag the opacity slider |
| Lock window | Press **L** or click the lock icon |

## Window Behavior

The Reframer window:

- Has no title bar or buttons (transparent and frameless)
- Floats above all other windows by default
- Can be resized by dragging edges (when unlocked)
- Can be moved by dragging the control bar or the handle

## Next Steps

- <doc:PlaybackControls> — Learn frame-accurate navigation
- <doc:ZoomAndPan> — Inspect video details
- <doc:LockMode> — Click through to apps below
- <doc:KeyboardShortcuts> — Master all shortcuts
