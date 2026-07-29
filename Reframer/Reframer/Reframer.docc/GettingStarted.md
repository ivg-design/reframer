# Getting Started

Load a local video and turn it into a reference overlay.

## Requirements

Reframer requires macOS 15.0 or later.

## Load your first video

1. Launch Reframer.
2. Activate the empty-state Open action, drop a file on the window, or press
   Command-O.
3. Choose a supported local file with a usable track. For YouTube, choose Open
   YouTube Video, paste an HTTPS link, review the first-use notice, and load it
   after the required Made for Kids preflight.
4. Use Space or the play control to play and pause.
5. Use Command-Page Down and Command-Page Up to step forward and backward.

An accepted file extension is not enough by itself: Reframer verifies that the
asset is playable and has a usable, decodable video track.
VP8/VP9 WebM is prepared as temporary ProRes 4444/PCM; this can need
substantial free disk space. YouTube never autoplays and uses adaptive quality.

## Position the reference

The video and control bar share one canonical window. Drag the grip at the left
edge of the control bar to move the complete overlay, including on the first
click while Reframer is inactive. Focus the grip and use Option-Arrow to move
one point or add Shift to move ten points; VoiceOver offers the same four
directions as named actions. macOS and window managers such as Mosaic also
move and resize the entire unlocked overlay instead of targeting the controls
separately. Resize from an edge, zoom with Shift-scroll, drag the loaded video
to pan, and set opacity from 2% through 100%. The ready surface always shows
its current frame, zoom, and lock state without intercepting pointer input.
At the preferred 1,060-point width, the controls occupy one 48-point row.
Below 920 points, they reflow into two rows totaling 96 points; every control
remains visible and accessibility-reachable through the 640-point minimum.

With local media loaded, press L to lock the overlay. The complete window then uses macOS's public
status-bar tier above all ordinary application windows, including normal,
floating, modal, and utility windows; cannot move or resize; and passes pointer
input through both the video and controls to the app underneath. Critical
system pop-up menus, drag UI, the screen saver, and assistive-technology
windows remain above it.

Use the enabled global lock shortcut, Command-Shift-L by default, to restore
interaction from the app underneath. Reframer refuses to lock unless that
exact configured chord is registered. If registration later becomes
unavailable, Reframer automatically unlocks and reports recovery.

YouTube stays unlocked so its required controls, captions, settings,
fullscreen, and links remain interactive. Use Always on Top When Unlocked for
that source.

## Learn more

- <doc:PlaybackControls>
- <doc:ZoomAndPan>
- <doc:LockMode>
- <doc:KeyboardShortcuts>
