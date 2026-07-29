# Playback Controls

Play, scrub, and navigate decoded video samples precisely.

## Play and pause

Press Space or activate the play/pause control. Invoking Play after end of file
returns to the first sample and starts playback.

The latest command remains authoritative while startup, replay, or scrub seeks
finish. A later Pause cannot be undone by a delayed player or seek completion.
A later Play attaches to the pending seek; physical playback remains paused
until the seek or scrub handoff completes.

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
a loaded, locked local video with exact or estimated sample navigation. They are not
registered or swallowed in any other state.

## YouTube

YouTube shares play/pause, time scrub, mute, volume, and window controls.
Its IFrame API is time-based, so exact frame entry/stepping is unavailable.
Quality is adaptive and cannot be forced by the supported API. Reframer keeps
standard player controls, links, branding, ads, settings, and WebKit element
fullscreen visible and does not autoplay. The web view fills the complete
video canvas and remains at least 200×200 points; YouTube owns its internal
aspect fit and letterboxing.
Click-through Lock is unavailable. Reframer unlocks before YouTube preflight
so required controls, captions, settings, fullscreen, and links stay
interactive. Use Always on Top When Unlocked instead.

While the timeline is dragged, YouTube preview seeks do not allow seek-ahead.
Release and discrete seeks do. YouTube's ready snapshot does not overwrite
saved native-media volume or mute preferences. Muting uses the official player
mute state without setting retained volume to zero, so the embedded player's
own Unmute restores the prior audible level.
