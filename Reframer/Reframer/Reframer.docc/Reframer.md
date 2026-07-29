# ``Reframer``

A precise video-reference overlay for macOS.

## Overview

Reframer loads local WebM, MP4/M4V/MOV, AVI, DV,
MPEG/transport-stream, and 3GP/3G2 media. VP8/VP9 WebM is prepared through the
bundled network-disabled helper as temporary ProRes 4444/PCM so alpha and local
inspection features are preserved. Reframer can also load an explicit YouTube
link after consent and a required Made for Kids preflight.
The video and control bar share one canonical window, so macOS and third-party
window managers move and resize them together while the overlay is unlocked.
The preferred 1,060-point width uses one 48-point control row. Below 920
points, the same controls reflow into two rows totaling 96 points and remain
visible and accessibility-reachable through the 640-point minimum.

Local native/prepared media supports exact or labeled estimated frame
navigation, zoom, pan, filters, and opacity. YouTube supports play/pause, time
seek, mute, volume, and window controls but not exact frames,
transforms, opacity, or filters. YouTube uses adaptive quality and standard
player UI with WebKit element fullscreen; it never autoplays.
Click-through Lock is disabled and any existing lock is released before
preflight so required player controls, captions, settings, fullscreen, and
links remain interactive. Use Always on Top When Unlocked for YouTube.

The app has outbound network access only for the explicit YouTube workflow.
Its documentation window renders bundled Help through native AppKit and never
fetches network content.

## Topics

### Start

- <doc:GettingStarted>
- <doc:LoadingVideos>
- <doc:YouTubePrivacy>

### Inspect

- <doc:PlaybackControls>
- <doc:ZoomAndPan>
- <doc:Opacity>
- <doc:Filters>

### Work over another app

- <doc:LockMode>
- <doc:KeyboardShortcuts>
