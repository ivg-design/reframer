# Reframer feature contract

This is the shipping feature list for Reframer 0.10.0. Planned work and
historical investigations are not product claims.

## Video

- Open or drop local MP4, M4V, and MOV files.
- Preflight the asset, require a playable video track, and show an actionable
  error for unsupported or corrupt media.
- Play, pause, replay from end of file, scrub with a coalesced preview, and
  finish a scrub on an exact decoded sample.
- Step by decoded sample timing rather than deriving every position from a
  rounded nominal frame rate.
- Preserve the requested frame across rapid step bursts and discard stale
  callbacks from superseded loads or seeks.

## Overlay

- Transparent, resizable video window with a dedicated, lock-aware control-bar
  grip for pointer, keyboard, and VoiceOver movement.
- Configurable Always on Top behavior.
- Opacity from 2% through 100%, persisted across launches.
- Click-through lock mode with visible, non-interactive frame, zoom, and lock
  status badges.
- Window placement is clamped to an available display after display changes.

## Inspection

- Zoom from 10% through 1000%, including fine scroll adjustment.
- Pan by primary-button dragging the loaded video or by keyboard while
  unlocked.
- Frame, zoom, and opacity fields support direct entry and modified-arrow
  increments.
- Quick filter menu plus an advanced, keyboard-accessible filter panel.
- Brightness, contrast, saturation, exposure, edges, sharpen, unsharp mask,
  monochrome, invert, line art, and noir effects.

## Input and accessibility

- A single command dispatcher handles key events, menu actions, and global
  shortcuts.
- Shortcut defaults can be changed, cleared, disabled, or restored.
- Invalid, reserved, duplicate, and unsafe global chords are rejected with an
  explanation.
- Global stepping is active only with a loaded video in lock mode.
- Custom controls expose task-oriented VoiceOver labels, values, state, and
  actions; keyboard focus enters and returns from panels predictably.
- Motion and focus treatments honor Reduce Motion and remain fully visible.

## Privacy and distribution

- Local processing only; no analytics or network dependency.
- Explicit runtime-resource allowlist.
- Hardened Runtime with no private entitlements.
- Universal Developer ID release, notarization, stapling, and Gatekeeper
  verification.

The machine-readable authority is
[`product-contract.json`](product-contract.json).
