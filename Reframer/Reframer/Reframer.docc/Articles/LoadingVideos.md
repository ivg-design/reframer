# Loading Videos

Open video files for overlay display.

## Overview

Reframer supports a wide range of video formats commonly used in production workflows. Load videos by drag-and-drop, file picker, or keyboard shortcut.

## Supported Formats

| Format | Extension | Notes |
|--------|-----------|-------|
| MPEG-4 | `.mp4` | Most common, highly recommended |
| QuickTime | `.mov` | Native macOS format |
| AVI | `.avi` | Windows format, widely supported |
| M4V | `.m4v` | Apple TV format |

### Codecs

The following codecs are supported:

- **H.264** — Universal compatibility
- **H.265/HEVC** — High efficiency, smaller files
- **ProRes** — Professional quality, larger files
- **AV1** — Next-gen codec (macOS 13+)

## Loading Methods

### Drag and Drop

1. Find your video file in Finder
2. Drag it onto the Reframer window
3. The video loads immediately

### File Picker

1. Click anywhere on the drop zone, or
2. Press **⌘O**
3. Navigate to your video file
4. Click **Open**

### From Finder

Double-click a video file if Reframer is set as the default app for that format.

## After Loading

When a video loads successfully:

- The drop zone disappears
- Video displays at its native aspect ratio
- Playback controls become active
- Frame counter shows total frames
- Video starts paused at frame 0

## Troubleshooting

### Video Won't Load

- Check the file format is supported
- Ensure the file isn't corrupted
- Try converting to MP4 with H.264

### Black Screen

- The video may have an unsupported codec
- Try a different video file to isolate the issue

### No Audio

- Audio is muted by default
- Click the speaker icon to unmute
- Adjust volume with the slider
