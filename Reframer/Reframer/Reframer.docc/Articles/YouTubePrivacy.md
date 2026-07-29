# YouTube Privacy and Terms

Understand the network requests, local preference, and temporary player data
used when you explicitly load a YouTube link.

## Before the player opens

Reframer contacts YouTube only after you paste a supported HTTPS video link,
review the first-use privacy and terms notice, and select Load Video. It stores
only the accepted notice version locally; it does not retain the pasted URL or
viewing history.

For every load, an ephemeral `URLSession` sends the parsed video identifier to
YouTube Data API `videos.list` for the required Made for Kids decision. The API
key travels in the `X-Goog-Api-Key` request header rather than the URL. Google
also necessarily receives ordinary HTTPS request and network metadata, such as
the source IP address. A missing key, failed request, unavailable video, or
unknown status stops the load before player HTML is created.

## Player data

An approved video uses YouTube's privacy-enhanced embed in a nonpersistent
WebKit data store. Session cookies or player data can exist while that player
runs, but are never persisted; Reframer clears all website data before every
embed. Reframer does not request or store YouTube login credentials.

YouTube and its media hosts receive ordinary player requests and can receive
the IP address, user agent, Reframer identity/Referer, and selected video
identifier. The player can display controls, links, branding, ads, settings,
and fullscreen UI. It does not autoplay.

## Player behavior

YouTube selects adaptive quality; the supported embed API does not let
Reframer force a quality level. The web view fills the complete video canvas
and remains at least 200×200 points, while YouTube owns its internal aspect fit
and letterboxing.

Reframer leaves standard player interaction visible, disables its own filters
and transforms, and keeps click-through Lock unavailable from preflight
through playback. Use Always on Top When Unlocked when the player should remain
above ordinary app windows.

## Terms

Using this feature is subject to the
[YouTube Terms of Service](https://www.youtube.com/t/terms). Google's handling
of data is described in the
[Google Privacy Policy](https://policies.google.com/privacy).
