# Loading Videos

Open a local MP4, M4V, or MOV reference.

## Open methods

- Activate the empty-state Open action.
- Press Command-O.
- Drop a file onto the unlocked Reframer window.

Reframer checks the selected asset asynchronously. A successful load requires
a playable AVFoundation asset with a usable video track. In a multi-track file,
playback, Core Image filtering, dimensions, and navigation use the same
selected track. If a newer
request replaces an in-progress load, callbacks from the older request are
ignored. Selecting a replacement stops playback and the new video lands
paused.

## Unsupported media

A container can hold many different codecs. If macOS cannot decode a usable
video track, Reframer leaves the player empty, reports the failure, and never
claims the file is ready. For the most portable result, use H.264 video in an
MP4 or MOV container.
