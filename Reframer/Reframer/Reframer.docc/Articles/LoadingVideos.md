# Loading Videos

Open a local reference or explicitly load a YouTube link.

## Open methods

- Activate the empty-state Open action.
- Press Command-O.
- Drop a file onto the unlocked Reframer window.
- Press Option-Command-O or choose Open YouTube Video for a YouTube link.

Reframer checks the selected asset asynchronously. A successful load requires
a playable AVFoundation asset with a usable video track. In a multi-track file,
playback, Core Image filtering, dimensions, and navigation use the same
selected track. If a newer
request replaces an in-progress load, callbacks from the older request are
ignored. Selecting a replacement stops playback and the new video lands
paused.

Supported local containers are WebM, MP4/M4V/MOV, AVI, DV,
MPEG/MPEG-2/transport-stream, and 3GP/3G2. VP8/VP9 WebM is prepared by the
bundled universal, network-disabled FFmpeg 8.1.2/libvpx 1.16.0 helper as a
temporary ProRes 4444 movie with PCM audio. Alpha is preserved. Preparation
requires at least 2 GB of temporary capacity, has a 64 GB output ceiling, can
be cancelled, stops after five minutes without output progress or 12 hours
total, and cleans temporary output when replaced or terminated.

YouTube requires first-use consent and a configured YouTube Data API key.
Every video receives a Made for Kids lookup before any player HTML is created;
failure or unknown status stops the load. The approved privacy-enhanced player
uses a nonpersistent data store that is cleared before every embed, no
autoplay, adaptive quality, standard controls, and WebKit element fullscreen.
The web view fills the complete video canvas and stays at least 200×200 points;
YouTube owns its internal aspect fit and letterboxing.
Filter and transform controls remain disabled from pending preflight through
playback. Reframer also unlocks and disables click-through Lock so required
controls, captions, settings, fullscreen, and links stay interactive; use
Always on Top When Unlocked.

Only the accepted consent-notice version is stored locally. Reframer does not
retain the pasted URL or viewing history. See <doc:YouTubePrivacy> for the
complete network and storage disclosure.

## Unsupported media

A container can hold many different codecs. If AVFoundation or the bounded
WebM preparation path cannot decode a usable track, Reframer leaves the player
empty, reports the failure, and never claims the file is ready.
