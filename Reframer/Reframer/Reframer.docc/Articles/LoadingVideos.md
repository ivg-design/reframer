# Loading Videos

Open a local MP4, M4V, or MOV reference.

## Open methods

- Activate the empty-state Open action.
- Press Command-O.
- Drop a file onto the unlocked Reframer window.

Reframer checks the selected asset asynchronously. A successful load requires
a playable AVFoundation asset with a video track. If a newer request replaces
an in-progress load, callbacks from the older request are ignored.

## Unsupported media

A container can hold many different codecs. If macOS cannot decode the video
track, Reframer leaves the current state intact and shows an actionable error.
For the most portable result, use H.264 video in an MP4 or MOV container.
