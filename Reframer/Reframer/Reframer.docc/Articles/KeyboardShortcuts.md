# Keyboard Shortcuts

Use one consistent command set from keys, menus, and global shortcuts.

## Defaults

| Action | Default | Shortcut Settings |
|---|---|---|
| Open local video | Command-O | Fixed menu command |
| Open YouTube video | Option-Command-O | Fixed menu command |
| Play / Pause | Space | Customizable |
| Step forward / backward | Command-Page Down / Command-Page Up | Customizable |
| Step ten | Add Shift to the step chord | Customizable multiplier |
| Pan | Arrow keys | Customizable |
| Pan 10 / 100 | Shift / Command-Shift + Arrow | Customizable multipliers |
| Reset zoom / view | 0 / R | Customizable |
| Toggle lock locally / globally | L / Command-Shift-L | Customizable |
| Shortcut settings | H | Customizable |
| Documentation | Command-? | Fixed Help command |
| Advanced filters | F | Customizable |
| Close current panel or recording | Escape | Customizable |

Shift-scroll zooms in 5% steps; Command-Shift-scroll makes a 0.1% adjustment.
An unmodified scroll over unlocked video steps samples. These pointer gestures
are fixed and are not Shortcut Settings rows. Command-O, Option-Command-O, and
Command-? are also fixed menu/Help commands. The panel contains 14 editable
action rows for playback, frame stepping, pan, resets, local/global Lock,
Shortcut Settings, Close Current Panel, and Filter Panel.

## Scope

Commands do not replace text-field editing shortcuts. Playback commands
require a ready source. Pan, zoom, filters, opacity, and frame commands require
local native or prepared media. Frame stepping works outside the app only when
a loaded, locked local video has exact or estimated sample navigation. Focused controls keep only the
activation and navigation keys they normally own, so H, F, L, R, 0, and
customized plain or Shift chords continue to work from buttons and other
unrelated controls. Text editors retain normal typing and editing.
System file and alert sheets bypass Reframer commands, and the documentation
view keeps native Space, arrow, and page scrolling.

Holding a toggle, panel, reset, or open shortcut does not fire it repeatedly.
Frame stepping and panning are the intentional repeatable actions.

## Customize

Open shortcut settings with H. An editable row can be changed, cleared,
disabled, or reset. Fixed menu/Help commands and pointer gestures are not
shown in the panel. Reframer rejects duplicate, reserved,
modifier-collapsing, and unsafe global chords. A replacement survives relaunch
and the old chord no longer fires. Global shortcuts can be disabled
independently. During normal operation,
the enabled lock chord stays registered in every video and lock state. The
frame-step variants are registered only in their actionable state, so Reframer
does not receive or swallow those keys through the global path while another
app is active. Registered hot keys require no Accessibility or Input Monitoring
permission. If another app already owns a chord, the same panel identifies the
failure and offers a retry action.

Shortcut Settings uses one shared five-column grid, resizes from 700×520
through 1100×1100, prefers 780×1020, remembers its validated size, and scrolls
at compact heights. Tab moves through enabled, shortcut, multiplier, and clear
controls in row-major order and is never recorded as a shortcut.

The complete overlay ignores pointer input while locked, including its control
bar. Keep an enabled global lock binding so Command-Shift-L, or your customized
replacement, can restore interaction from the app underneath.
Reframer will not enter lock unless that exact configured chord is registered.
Registration loss, conflict, recording suspension, or disabling global
shortcuts while locked causes an immediate automatic unlock and a recovery
report. Unlocking is always permitted.

Lock commands apply only to native or prepared local media. They are disabled
from pending YouTube preflight through playback so required player controls,
captions, settings, fullscreen, and links remain interactive.
