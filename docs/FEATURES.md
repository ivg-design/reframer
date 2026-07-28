# Reframer feature contract

This is the implemented release-candidate feature contract for Reframer
0.10.0. It does not claim publication or Apple distribution acceptance.
Planned work and historical investigations are not product claims.

## Video

- Open or drop local MP4, M4V, and MOV files.
- Preflight the asset, require an enabled or fallback usable video track, and
  show an actionable error for unsupported or corrupt media.
- Use the same selected video track for playback, Core Image filtering,
  transformed display dimensions, nominal rate, and frame indexing in
  multi-track files, with audio limited and aligned to that video timeline.
- Play, pause, replay from end of file, scrub with a coalesced preview, and
  finish a scrub on an exact decoded sample when exact indexing is available.
- Step by decoded presentation timing after exact indexing rather than deriving
  every position from a rounded nominal frame rate.
- Keep navigation available through a visibly labeled constant-rate estimate
  while indexing, if sample cursors are unavailable, or when the
  2,000,000-sample exact-index memory ceiling is reached.
- Preserve the requested frame across rapid step bursts and discard stale
  callbacks from superseded loads or seeks.
- Stop playback when a replacement is selected and land the new video paused.

## Overlay

- One canonical transparent overlay window contains both the video and control
  bar. macOS and third-party window managers such as Mosaic therefore move and
  resize the complete overlay while it is unlocked.
- The preferred 1,060-point width uses one 48-point control row. Widths from
  the 640-point minimum through 919 points use two rows totaling 96 points;
  every control remains visible and accessibility-reachable in either layout.
- A dedicated, lock-aware control-bar grip provides pointer, keyboard, and
  VoiceOver movement.
- Configurable Always on Top When Unlocked behavior.
- Opacity from 2% through 100%, persisted across launches.
- Lock mode raises the complete overlay to macOS's public status-bar window
  tier, above all ordinary application windows—including normal, floating,
  modal, and utility windows—regardless of the saved Always on Top When
  Unlocked preference. It makes the video and controls pointer-transparent and
  prevents moving or resizing.
- Critical system-owned UI remains above the overlay: pop-up menus, drag UI,
  the screen saver, and assistive-technology windows.
- The enabled global lock shortcut restores interaction from the app
  underneath; visible frame, zoom, and lock status remain non-interactive.
- Lock entry requires the exact configured global Lock/Unlock chord to be
  registered. If it becomes unavailable, conflicts, is suspended during
  shortcut recording, or global shortcuts are disabled while locked, Reframer
  automatically unlocks and reports recovery guidance.
- Window placement is clamped to an available display after display changes.

## Inspection

- Zoom from 10% through 1000%, including fine scroll adjustment.
- Pan by primary-button dragging the loaded video or by keyboard while
  unlocked.
- Frame, zoom, and opacity fields support direct entry and modified-arrow
  increments.
- Native AppKit Quick Filter pop-up with primary-click and keyboard selection,
  plus a separate keyboard-accessible advanced filter panel.
- Brightness, contrast, saturation, exposure, edges, sharpen, unsharp mask,
  monochrome, invert, line art, and noir effects.

## Input and accessibility

- A single command dispatcher handles key events, menu actions, and global
  shortcuts.
- Shortcut defaults can be changed, cleared, disabled, or restored.
- Invalid, reserved, duplicate, and unsafe global chords are rejected with an
  explanation.
- Held non-repeat actions are consumed once without leaking into AppKit menu
  autorepeat; frame stepping and panning retain intentional repeat behavior.
- The enabled global lock chord remains registered during normal operation.
  Frame-step variants are registered only with a loaded, locked video whose
  exact or estimated sample navigation is available, and are not consumed
  otherwise.
- Unlocking is always permitted. Entering whole-overlay click-through is
  rejected when its configured global recovery chord is unavailable.
- Registration conflicts are reported with an accessible retry action; broad
  keyboard monitoring and privacy permission prompts are not used.
- Registration updates retain unchanged hot keys and held-key state; system
  sheets and native AppKit documentation keep their conventional keyboard
  navigation.
- Custom controls expose task-oriented VoiceOver labels, values, state, and
  actions; keyboard focus enters and returns from panels predictably.
- Sliders expose their numeric range and orientation, the frame/zoom/lock
  ready-state badges are independently reachable, and the empty-state Open
  action reports enabled.
- Dynamic shortcut/filter failures are announced, auxiliary windows have
  meaningful accessibility names, and the key or frontmost panel closes first.
- Motion, contrast, transparency, and focus treatments follow live macOS
  accessibility display settings and remain fully visible.

## Privacy and distribution

- Local processing only; no analytics or network dependency.
- App Sandbox with user-selected, read-only video access.
- Bundled Help renders through native AppKit without WebKit or a network
  entitlement.
- Explicit runtime-resource allowlist.
- Hardened Runtime with only the two allowlisted sandbox entitlements.
- Release acceptance requires a universal Developer ID build, notarization,
  stapling, and Gatekeeper verification. These external Apple checks are not
  implied by a repository or unsigned-build pass.

The machine-readable authority is
[`product-contract.json`](product-contract.json).
