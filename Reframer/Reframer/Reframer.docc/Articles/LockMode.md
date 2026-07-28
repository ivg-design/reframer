# Lock Mode

Keep the complete reference above ordinary app windows while working through
it.

Press L or activate the lock control while Reframer is active. Press
Command-Shift-L to toggle lock from another app when global shortcuts are
enabled.

When locked:

- the overlay uses macOS's public status-bar tier above all ordinary
  application windows, including normal, floating, modal, and utility windows,
  even when Always on Top When Unlocked is off;
- pointer events over the video and control bar pass to the app underneath;
- moving, resizing, zooming, and panning are disabled;
- the frame, zoom, and locked-status badges remain visible without intercepting
  input;
- Command-Page Down and Command-Page Up can step globally when exact or
  estimated sample navigation is available.

Critical system-owned pop-up menus, drag UI, the screen saver, and
assistive-technology windows remain above the locked overlay.

Because the entire control bar is pointer-transparent, do not rely on its lock
button for recovery. Use the enabled global lock shortcut—Command-Shift-L by
default—to unlock from the app underneath. Unlocking restores interaction,
moving, and resizing, and returns the window to the saved Always on Top When
Unlocked preference.

Reframer refuses to enter lock unless the exact configured global Lock/Unlock
chord is registered. If that registration later disappears or conflicts, is
suspended while recording a shortcut, or global shortcuts are disabled,
Reframer automatically unlocks and reports the configured chord plus recovery
guidance. Unlocking itself is always permitted.

The enabled global lock chord stays registered during normal operation. Frame
chords are registered only while the video is loaded, navigation is available,
and the overlay is locked. They are removed rather than swallowed in all other
states. Registered hot keys require no Accessibility or Input Monitoring
permission. Shortcut Settings reports a registration conflict and provides a
retry action when another app owns a chord.
