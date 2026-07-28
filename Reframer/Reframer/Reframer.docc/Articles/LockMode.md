# Lock Mode

Make the video click-through while keeping playback control available.

Press L or activate the lock control while Reframer is active. Press
Command-Shift-L to toggle lock from another app when global shortcuts are
enabled.

When locked:

- video-area pointer events pass to the app underneath;
- moving, resizing, zooming, and panning are disabled;
- the status overlay remains visible without intercepting input;
- Command-Page Down and Command-Page Up can step a loaded video globally.

Global frame stepping is ignored when no video is loaded or the overlay is
unlocked. Reframer reports whether the required macOS permission is enabled and
provides a route to retry or open System Settings.
