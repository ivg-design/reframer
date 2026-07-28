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
unlocked. Frame stepping works outside the app only when a loaded, locked video
has exact or estimated sample navigation. Focused controls keep only the
activation and navigation keys they normally own, so H, F, L, R, 0, and
customized plain or Shift chords continue to work from buttons and other
unrelated controls. Text editors retain normal typing and editing.
System file and alert sheets bypass Reframer commands, and the documentation
view keeps native Space, arrow, and page scrolling.

Holding a toggle, panel, reset, or open shortcut does not fire it repeatedly.
Frame stepping and panning are the intentional repeatable actions.

## Customize

Open shortcut settings with H. A shortcut can be changed, cleared, disabled,
or reset. Reframer rejects duplicate, reserved, modifier-collapsing, and unsafe
global chords. A replacement survives relaunch and the old chord no longer
fires. Global shortcuts can be disabled independently. During normal operation,
the enabled lock chord stays registered in every video and lock state. The
frame-step variants are registered only in their actionable state, so Reframer
does not receive or swallow those keys through the global path while another
app is active. Registered hot keys require no Accessibility or Input Monitoring
permission. If another app already owns a chord, the same panel identifies the
failure and offers a retry action.

The complete overlay ignores pointer input while locked, including its control
bar. Keep an enabled global lock binding so Command-Shift-L, or your customized
replacement, can restore interaction from the app underneath.
Reframer will not enter lock unless that exact configured chord is registered.
Registration loss, conflict, recording suspension, or disabling global
shortcuts while locked causes an immediate automatic unlock and a recovery
report. Unlocking is always permitted.
