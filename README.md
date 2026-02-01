# Reframer

A lightweight macOS video overlay app for frame-accurate video reference. Designed for animators, video editors, and anyone who needs to compare video frames with their work.

## Features

- **Transparent Overlay**: Always-on-top transparent window that overlays other applications
- **Frame-Accurate Playback**: Step through video frame-by-frame using keyboard shortcuts or scroll wheel
- **Zoom & Pan**: Inspect video details with zoom (up to 1000%) and pan controls
- **Adjustable Opacity**: Set video transparency from 2-100%
- **Persistent Settings**: Remembers opacity, volume, and window position
- **Lock Mode**: Click-through mode lets you interact with apps underneath
- **Drag & Drop**: Open videos by dragging files onto the window
- **Liquid Glass UI**: Modern macOS Tahoe-style controls with Sequoia fallback
- **YouTube Links**: Long-press Open to paste a YouTube URL

## System Requirements

- macOS 15.0 (Sequoia) or later
- macOS 26.0 (Tahoe) recommended for Liquid Glass visual effects
- WebM/MKV playback requires VLCKit (prompted on first use)

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open File | Cmd+O |
| Play/Pause | Space |
| Frame Forward | Right Arrow or Scroll Down |
| Frame Back | Left Arrow or Scroll Up |
| 10 Frames | Shift+Arrow |
| Zoom In | Up Arrow or + |
| Zoom Out | Down Arrow or - |
| Reset Zoom | 0 |
| Reset View | R |
| Toggle Lock | L |
| Help | H or ? |

## Mouse/Scroll Controls

| Action | Gesture |
|--------|---------|
| Frame Step | Scroll (no modifiers) |
| Zoom | Shift+Scroll (5% steps) |
| Fine Zoom | Cmd+Shift+Scroll (0.1% steps) |
| Pan | Drag video (when zoomed > 100%) |
| Move Window | Drag control bar background |

## Global Shortcuts

| Action | Shortcut |
|--------|----------|
| Toggle Lock | Cmd+Shift+L |
| Frame Forward | Cmd+PageDown |
| Frame Back | Cmd+PageUp |

## Building

1. Open `Reframer/Reframer.xcodeproj` in Xcode 15.0+
2. Select your signing team
3. Build and run (Cmd+R)

## Documentation

See the `docs/` folder for detailed documentation:
- `FEATURES.md` - Feature specifications
- `FEATURE_TESTS.md` - Test plan
- `MASTER_IMPLEMENTATION_PLAN.md` - Implementation details

## License

MIT License
