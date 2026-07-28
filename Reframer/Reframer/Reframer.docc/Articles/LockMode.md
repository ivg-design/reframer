# Lock Mode

Make the video click-through while keeping playback control available.

Press L or activate the lock control while Reframer is active. Press
Command-Shift-L to toggle lock from another app when global shortcuts are
enabled.

When locked:

- video-area pointer events pass to the app underneath;
- moving, resizing, zooming, and panning are disabled;
- the frame, zoom, and locked-status badges remain visible without intercepting
  input;
- Command-Page Down and Command-Page Up can step a loaded video globally.

Global frame stepping is ignored when no video is loaded or the overlay is
unlocked. Reframer registers only these exact global chords, so it requires no
Accessibility or Input Monitoring permission. Shortcut Settings reports a
registration conflict and provides a retry action when another app owns a
chord.
