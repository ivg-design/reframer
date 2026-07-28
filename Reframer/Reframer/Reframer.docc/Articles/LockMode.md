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
- Command-Page Down and Command-Page Up can step globally when exact or
  estimated sample navigation is available.

The enabled global lock chord stays registered during normal operation. Frame
chords are registered only while the video is loaded, navigation is available,
and the overlay is locked. They are removed rather than swallowed in all other
states. Registered hot keys require no Accessibility or Input Monitoring
permission. Shortcut Settings reports a registration conflict and provides a
retry action when another app owns a chord.
