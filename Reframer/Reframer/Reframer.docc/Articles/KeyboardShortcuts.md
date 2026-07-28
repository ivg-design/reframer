# Keyboard Shortcuts

Use one consistent command set from keys, menus, and global shortcuts.

## Defaults

| Action | Default |
|---|---|
| Open | Command-O |
| Play / Pause | Space |
| Step forward / backward | Command-Page Down / Command-Page Up |
| Step ten | Add Shift to the step chord |
| Pan | Arrow keys |
| Pan 10 / 100 | Shift / Command-Shift + Arrow |
| Reset zoom / view | 0 / R |
| Toggle lock locally / globally | L / Command-Shift-L |
| Shortcut settings | H |
| Documentation | Command-? |
| Advanced filters | F |
| Close current panel or recording | Escape |

Shift-scroll zooms in 5% steps; Command-Shift-scroll makes a 0.1% adjustment.
An unmodified scroll over unlocked video steps samples.

## Scope

Commands do not replace text-field editing shortcuts. Playback and inspection
commands require a loaded video. Pan and zoom require the overlay to be
unlocked. Frame stepping works outside the app only with a loaded, locked
overlay. Focused controls keep only the activation and navigation keys they
normally own, so H, F, L, R, 0, and customized plain or Shift chords continue
to work from buttons and other unrelated controls. Text editors retain normal
typing and editing.

## Customize

Open shortcut settings with H. A shortcut can be changed, cleared, disabled,
or reset. Reframer rejects duplicate, reserved, modifier-collapsing, and unsafe
global chords. A replacement survives relaunch and the old chord no longer
fires. Global shortcuts can be disabled independently. Reframer registers only
the enabled global chords, so Accessibility and Input Monitoring permission
are not required. If another app already owns a chord, the same panel
identifies the failure and offers a retry action.
