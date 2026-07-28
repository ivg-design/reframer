# Playback Controls

Play, scrub, and navigate decoded video samples precisely.

## Play and pause

Press Space or activate the play/pause control. Invoking Play after end of file
returns to the first sample and starts playback.

## Step

| Action | Default |
|---|---|
| Forward one | Command-Page Down |
| Backward one | Command-Page Up |
| Forward ten | Command-Shift-Page Down |
| Backward ten | Command-Shift-Page Up |

An unmodified scroll over unlocked video also steps. Scroll down advances and
scroll up reverses.

After exact indexing, Reframer navigates the selected video track’s decoded
presentation samples rather than repeatedly adding a rounded nominal frame
duration. During indexing, when sample cursors are unavailable, or when a very
long video exceeds the bounded exact-index table, the toolbar identifies that
frame numbers use a constant-rate estimate. Rapid input updates one desired
cursor so stale seek completions cannot move the picture backward.

## Scrub

Drag the timeline for responsive preview seeks. Releasing it resolves the
nearest boundary in the active exact or labeled estimated timeline. The frame
field accepts a frame number directly.

The global step chords work while another app is active only when Reframer has
a loaded, locked video with exact or estimated sample navigation. They are not
registered or swallowed in any other state.
