# Reframer product contract

This document is the human-readable authority for Reframer 0.10.0. Its
machine-readable counterpart is
[`product-contract.json`](product-contract.json).

## Platform and media

- Minimum system: macOS 15.0.
- Supported containers: MP4, M4V, and MOV.
- Decoder and compositor: AVFoundation and Core Image.
- A supported extension is not a promise that every embedded codec is
  decodable. Reframer preflights the selected asset and reports failure before
  presenting it as loaded.
- Playback is local and offline.

## Commands

| Command | Default | Guard |
|---|---|---|
| Open video | Command-O | App active |
| Play / Pause | Space | App active, video loaded |
| Step forward 1 | Command-Page Down | App active with sample navigation; global only when loaded, locked, and sample navigation is available |
| Step backward 1 | Command-Page Up | App active with sample navigation; global only when loaded, locked, and sample navigation is available |
| Step forward / backward 10 | Add Shift | Same guard as frame step |
| Pan 1 | Arrow keys | App active, loaded, unlocked |
| Pan 10 | Shift + Arrow | App active, loaded, unlocked |
| Pan 100 | Command-Shift + Arrow | App active, loaded, unlocked |
| Reset zoom | 0 | App active, loaded, unlocked |
| Reset view | R | App active, loaded, unlocked |
| Toggle lock | L | App active |
| Toggle lock globally | Command-Shift-L | Global shortcuts enabled |
| Shortcut settings | H | App active |
| Documentation | Command-? | App active |
| Filter panel | F | App active, loaded |
| Close current panel or recording | Escape | Contextual |

Shift-scroll zooms in 5% steps. Command-Shift-scroll uses 0.1% steps. An
unmodified scroll over unlocked video steps samples. Primary-button dragging
the loaded video pans it while unlocked; the dedicated control-bar grip moves
the overlay window. The grip accepts the first click when Reframer is inactive,
supports Option-Arrow keyboard movement while focused (add Shift for 10-point
steps), and exposes directional VoiceOver actions.

Shortcut editing must prevent collisions, reserved system chords, modifier
collapse, and unsafe unmodified global keys. A customized chord replaces its
old chord completely and fires once. Clearing or disabling an action survives
relaunch.

Global actions use exclusive system-registered hot keys. During normal
operation, the enabled global lock chord stays registered in every video and
lock state. The four enabled frame-step variants are registered only while a
video is loaded, the overlay is locked, and exact or estimated sample
navigation is available. They are unregistered outside that actionable state,
so Reframer neither receives nor swallows those key combinations then.

Registrations are rebuilt when shortcut settings or the actionable playback
state changes. They are suspended while the shortcut recorder is listening and
removed on shutdown. Reframer does not install a broad global event monitor and
requires neither Accessibility nor Input Monitoring permission. Registration
conflicts are surfaced in Shortcut Settings with a retry action.

## State

- Loading, ready, playing, paused, ended, and failed are distinct states.
- A new load cancels or invalidates all callbacks from the previous generation.
- The desired sample index is the authority during burst input.
- A scrub may use tolerant preview seeks while dragging; release resolves to
  the exact target sample.
- Ended media replays from the first sample when Play is invoked.

Opacity, last audible volume, mute, Always on Top, window placement, filter
settings, and shortcut customization persist. Values are validated and clamped
when restored.

## Accessibility and input

All controls have a task-oriented label, role, current value/state where
applicable, and keyboard/VoiceOver action. Opening a panel moves focus into it;
closing returns focus to its invoker. Decorative and status overlays never
intercept pointer input. Ready video shows frame, zoom, and lock status, with
the locked state persistently visible. Focused controls do not dim. Reduce
Motion removes nonessential fades and pulses, and Reduce Transparency uses
opaque status backgrounds.

A focused text editor retains text and standard editing commands. Other
controls retain only their conventional activation and navigation keys; they
do not suppress plain or Shift-based Reframer shortcuts they do not own.

## Release

A shippable candidate must be a universal, Hardened Runtime Developer ID build
in App Sandbox with only user-selected, read-only file access. Release
acceptance requires successful notarization, stapling, Gatekeeper assessment,
and an internal-document/test-artifact leakage check. Repository, unsigned, or
ad hoc signed build validation is not evidence that these external Apple gates
ran.
