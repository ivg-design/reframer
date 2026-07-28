# ``Reframer``

A precise, local video-reference overlay for macOS.

## Overview

Reframer loads MP4, M4V, and MOV files through AVFoundation and keeps the
picture visible above another app. You can play, scrub, navigate indexed
presentation samples or a labeled estimate, zoom, pan, filter, adjust opacity,
and lock the complete window into a status-bar-tier click-through reference
above ordinary application windows.
The video and control bar share one canonical window, so macOS and third-party
window managers move and resize them together while the overlay is unlocked.
The preferred 1,060-point width uses one 48-point control row. Below 920
points, the same controls reflow into two rows totaling 96 points and remain
visible and accessibility-reachable through the 640-point minimum.

Reframer is local and offline. It preflights each asset and reports an
unsupported or corrupt asset, or a missing usable video track, before marking
the video ready.
Its documentation window renders the bundled Help pages with native AppKit and
requires no network entitlement.

## Topics

### Start

- <doc:GettingStarted>
- <doc:LoadingVideos>

### Inspect

- <doc:PlaybackControls>
- <doc:ZoomAndPan>
- <doc:Opacity>
- <doc:Filters>

### Work over another app

- <doc:LockMode>
- <doc:KeyboardShortcuts>
