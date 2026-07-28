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

Reframer navigates the asset’s decoded sample timing rather than repeatedly
adding a rounded nominal frame duration. Rapid input updates one desired-sample
cursor so stale seek completions cannot move the picture backward.

## Scrub

Drag the timeline for responsive preview seeks. Releasing it resolves the
exact target sample. The frame field accepts a sample number directly.

The global step chords work while another app is active only when Reframer has
a loaded, locked video with exact or estimated sample navigation. They are not
registered or swallowed in any other state.
