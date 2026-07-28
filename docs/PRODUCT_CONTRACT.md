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
| Step forward 1 | Command-Page Down | App active; global only when loaded and locked |
| Step backward 1 | Command-Page Up | App active; global only when loaded and locked |
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
unmodified scroll over unlocked video steps samples.

Shortcut editing must prevent collisions, reserved system chords, modifier
collapse, and unsafe unmodified global keys. A customized chord replaces its
old chord completely and fires once. Clearing or disabling an action survives
relaunch.

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
intercept pointer input. Focused controls do not dim. Reduce Motion removes
nonessential fades and pulses.

## Release

The shipping app is a universal, Hardened Runtime Developer ID build with an
empty entitlement set. It is notarized, stapled, Gatekeeper-assessed, and
checked for internal-document or test-artifact leakage.
