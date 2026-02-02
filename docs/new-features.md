# Planned Features

## Navigable Markers with Shortcuts

Add the ability to set markers on the timeline and navigate between them with keyboard shortcuts.

- **Set marker**: Press `M` to add a marker at current position
- **Delete marker**: `Shift+M` to remove marker at/near current position
- **Navigate**: `[` / `]` to jump to previous/next marker
- **Clear all**: Menu option to clear all markers
- Markers persist per video session (or optionally saved to sidecar file)
- Visual indicator on timeline showing marker positions

---

## Math Operations in Frame Input

Allow simple arithmetic in the frame input field for quick relative navigation.

**Supported operations:**
- `+N` - Jump forward N frames (e.g., `+20` adds 20 frames)
- `-N` - Jump backward N frames (e.g., `-56` goes back 56 frames)
- `*N` - Multiply current frame (e.g., `*2` doubles current position)
- `/N` - Divide current frame (e.g., `/2` halves current position)

**Behavior:**
- Type the operation and press Enter
- Field shows result after calculation
- Invalid expressions show brief error shake
- Works in both frame and timecode input fields

---

## Time Display Modes

Add a toggle to cycle through different time display formats in the control bar.

**Display modes:**
1. **Frame only**: `1234` - Just the frame number
2. **Time + Frame**: `1:23.45 [1234]` - Timecode with frame in brackets
3. **Time only**: `1:23.456` - Timecode with milliseconds
4. **SMPTE**: `00:01:23:15` - Hours:Minutes:Seconds:Frames (for broadcast)

**UI:**
- Click on time display to cycle modes
- Or use keyboard shortcut `T` to toggle
- Preference persisted across sessions

---

## Media Info Panel

Display detailed file information similar to `ffprobe` output.

**Information to show:**
- **Container**: Format, duration, bitrate, file size
- **Video stream**: Codec, profile, resolution, frame rate, bit depth, pixel format
- **Color**: Color space, color primaries, transfer characteristics, matrix coefficients
- **Audio stream(s)**: Codec, sample rate, channels, bitrate
- **Metadata**: Creation date, encoder, other tags

**UI options:**
- Accessible via `I` key or menu item
- Floating panel or modal overlay
- Copy button to copy info as text
- Could use AVAsset metadata + optional ffprobe for extended info

**Example display:**
```
File: example.mp4 (234.5 MB)
Duration: 00:05:23.456 | 9,704 frames

VIDEO
  Codec: H.264 (High Profile)
  Resolution: 1920x1080 @ 29.97 fps
  Bit depth: 8-bit | Pixel format: yuv420p
  Bitrate: 5.8 Mbps (VBR)

COLOR
  Space: BT.709 | Primaries: BT.709
  Transfer: BT.709 | Matrix: BT.709

AUDIO
  Codec: AAC-LC @ 48000 Hz
  Channels: Stereo | Bitrate: 192 kbps
```
