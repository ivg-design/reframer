# Reframer

Reframer is a native macOS video-reference overlay for animation, motion,
editing, and visual comparison work. It keeps local media or an explicitly
loaded YouTube video above your workspace. Local media can become click-through
while you work in the app underneath; YouTube stays unlocked and interactive.

## What it does

- Loads local WebM, MP4/M4V/MOV, AVI, DV, MPEG/transport-stream, and 3GP/3G2
  containers. Native formats use AVFoundation; VP8/VP9 WebM is prepared by the
  bundled universal, network-disabled FFmpeg 8.1.2/libvpx 1.16.0 helper as a
  temporary ProRes 4444 movie with PCM audio, preserving alpha. Preparation
  stops after five minutes without output progress or 12 hours total
- Opens an explicitly supplied YouTube link in a privacy-enhanced,
  nonpersistent WebKit player, cleared before every embed, after first-use
  consent and a required
  per-video Made for Kids Data API check. YouTube chooses adaptive quality;
  its supported embed API does not let Reframer force maximum quality. Only
  the accepted consent-notice version is stored locally; pasted links and
  viewing history are not retained
- Indexes decoded presentation samples for exact fractional-rate and
  variable-timing navigation, with a clearly labeled bounded estimate when
  exact indexing is unavailable
- Plays, pauses, scrubs, zooms, pans, filters, mutes, and adjusts opacity
- Persists opacity, volume, window placement, filter settings, and customized
  shortcuts
- Presents the video and control bar as one canonical overlay window, so
  macOS and window managers such as Mosaic move and resize the complete
  unlocked overlay
- Uses the preferred 1,060-point width with one 48-point control row for its
  initial layout and restores saved geometry thereafter; below 920 points the
  same controls reflow into two rows totaling 96 points, with every control
  still visible and accessibility-reachable down to the 640-point minimum width
- For native or prepared local media, locks the complete overlay at macOS's
  public status-bar window tier, above
  all ordinary application windows—including normal, floating, modal, and
  utility windows; makes both the video and control bar pointer-transparent;
  and disables moving and resizing until the global lock shortcut restores
  interaction
- Refuses to enter whole-overlay click-through unless the exact configured
  global Lock/Unlock chord is registered, and automatically unlocks with a
  recovery report if that registration later becomes unavailable
- Treats Always on Top When Unlocked as an unlocked-state preference; lock
  mode forces the overlay on top regardless of that saved preference
- Keeps the enabled global lock chord available from any video or lock state
- Registers global frame-step chords only while a video is loaded, the overlay
  is locked, and exact or estimated sample navigation is available
- Never monitors general keyboard input from other apps or reserves inactive
  global frame-step chords
- Exposes keyboard and VoiceOver names, values, state, and actions, including
  complete slider ranges/orientation and independently reachable ready-state
  badges
- Presents resizable Shortcut Settings in one shared five-column grid, with
  aligned enabled, shortcut, action, multiplier, and clear columns, row-major
  keyboard traversal, remembered size, and scrolling at compact heights

Reframer never downloads native executable components or plug-ins. YouTube
necessarily loads remote web content and IFrame API JavaScript in WebKit. A recognized local container
can still be rejected when its codec or media data is unsupported. For native
or prepared local media, the enabled usable track selected for playback and
Core Image filtering is also the source of dimensions and exact or estimated
frame navigation.

YouTube uses the same play/pause, time-scrub, mute, volume, and window controls
where the IFrame Player API permits. It is intentionally time-based:
exact frame stepping, zoom/pan, opacity, and Core Image filters are unavailable,
and YouTube's standard controls, links, branding, ads, settings, and fullscreen
behavior remain visible with WebKit element fullscreen enabled. Filter and
transform controls remain disabled from pending preflight through playback.
Click-through Lock is also unavailable: Reframer automatically unlocks before
YouTube preflight and disables Lock so required player controls, captions,
settings, fullscreen, and links remain interactive. Use Always on Top When
Unlocked to keep YouTube above other ordinary app windows.
Timeline-drag previews avoid seek-ahead for a stable scrub, while release and
discrete seeks allow it. A YouTube ready snapshot does not overwrite the saved
native-media volume or mute preference. Muting uses the official player mute
state without setting its retained volume to zero, so the embedded player's
own Unmute control restores the prior audible level.

## Requirements

- macOS 15.0 or later
- Xcode 16 or later to build from source

## Essential controls

| Action | Default | Shortcut Settings |
|---|---|---|
| Open video | Command-O | Fixed menu command |
| Open YouTube video | Option-Command-O | Fixed menu command |
| Play or pause | Space | Customizable |
| Step forward | Command-Page Down | Customizable |
| Step backward | Command-Page Up | Customizable |
| Step 10 frames | Add Shift | Customizable multiplier |
| Pan | Arrow keys | Customizable |
| Pan 10 / 100 points | Shift / Command-Shift + Arrow | Customizable multipliers |
| Zoom / fine zoom | Shift / Command-Shift + Scroll | Fixed pointer gesture |
| Reset zoom / view | 0 / R | Customizable |
| Toggle local-media lock locally / globally | L / Command-Shift-L | Customizable |
| Advanced filters | F | Customizable |
| Shortcut settings | H | Customizable |
| Documentation | Command-? | Fixed Help command |

The enabled global lock chord stays registered during normal operation. The
four frame-step variants are registered only when a loaded, locked video has
exact or estimated sample navigation, so those key combinations remain
available to other apps in every other state. Global shortcuts use privacy-safe
registered hot keys and require neither Accessibility nor Input Monitoring
permission. Registration conflicts are reported in Shortcut Settings with a
retry action. The rows marked Customizable can be changed or disabled there;
the three fixed menu/Help commands and pointer-only zoom gestures are not
shown as editable rows. Because every pointer
event passes through the complete locked local-media overlay, use the enabled global lock
chord—Command-Shift-L by default—to unlock it from the app underneath.
Reframer will not lock unless that exact configured chord is registered. If
registration later disappears, conflicts, is suspended during shortcut
recording, or global shortcuts are disabled, Reframer immediately unlocks and
reports how to restore recovery before locking again.
Critical system-owned UI still takes precedence over the overlay, including
pop-up menus, drag UI, the screen saver, and assistive-technology windows.

Reframer runs in App Sandbox and receives read-only access only to videos the
user explicitly opens or drops. The app has a network-client entitlement only
for the explicit YouTube workflow: its ephemeral Data API preflight and
privacy-enhanced player contact YouTube, Google APIs, and YouTube media hosts.
The Data API query contains the parsed video identifier, its key is sent in a
header, and Google receives ordinary HTTPS request/network metadata such as
source IP. The nonpersistent player can hold session data while it runs, but
clears it before every embed and never persists it.
There is no analytics, update, or native executable-download path. The documentation
window itself renders the bundled Help pages with native AppKit and never
fetches network content; allowlisted policy links open in the system browser.

See [Product Contract](docs/PRODUCT_CONTRACT.md) for exact states and guards.
See [Threat Model](docs/THREAT_MODEL.md) for the keyboard and file-access trust
boundaries.

## Build and test

```bash
xcodebuild build \
  -project Reframer/Reframer.xcodeproj \
  -scheme Reframer \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

TEST_SCOPE=unit scripts/runner_test.sh
```

The normal CI suite builds Debug and universal Release, runs static analysis,
validates the product and bundle contracts, builds DocC, and runs unit tests.
The test runner retains its text log but unregisters temporary Reframer apps
and removes its sentinel-owned DerivedData on every exit, so a background run
does not add old app builds to LaunchServices or Spotlight.
The UI suite runs separately and only with fresh operator authorization.
XCUITest launches and foregrounds Reframer, takes keyboard focus, and is not a
background test merely because it was started from Terminal. Run it only in an
unlocked, logged-in macOS session whose operator has explicitly approved that
specific run.

Source builds intentionally leave `YOUTUBE_DATA_API_KEY` empty by default, so
YouTube loading fails closed until a development key is supplied. For local
development, set `YOUTUBE_DATA_API_KEY` in an untracked `.xcconfig` selected by
your Xcode configuration, or as an Xcode user-defined build setting. Never
commit the key. Release packaging instead requires
`REFRAMER_YOUTUBE_DATA_API_KEY` and injects it through a temporary configuration
file.

## Release

Developer ID signing and notarization are handled by
[`scripts/package_release.sh`](scripts/package_release.sh). The script refuses
dirty sources and a missing or unexpanded `REFRAMER_YOUTUBE_DATA_API_KEY`,
injects that secret as an Xcode build setting without committing it, validates
the universal app bundle and nested WebM helper, submits it for
notarization, staples and revalidates the ticket-bearing bundle, runs
Gatekeeper assessment, packages the result, then extracts and rechecks the
final ZIP. Release DerivedData remains inside a scoped temporary directory;
temporary app registrations are removed during cleanup so packaging does not
seed older Reframer builds into LaunchServices or Spotlight.
Local packaging also refuses source that is not clean, on `main`, and equal to
the locally fetched `origin/main`.

The audit records the historical build-1 and build-2 review runs, the packaging
gap build 1 exposed, and the live product defects found after build 2 passed
Apple's distribution checks. Build 3 from source commit `3010955` passed its
background validation and Apple distribution gates, and the notarized
`0.10.0 (3)` app was installed in `/Applications` for operator review.
Foreground/manual interaction remains an explicit candidate gate. Only
evidence emitted for a particular artifact proves that artifact. This local
review build does not create a version tag, GitHub release, or published
distribution.

Version 0.11.0 build 4 is the current source candidate. It adds aligned,
resizable Shortcut Settings, expanded local containers, transparent WebM
preparation, and consent-gated YouTube playback. Its candidate-specific
validation belongs in
[Build 4 Readiness](docs/AUDIT_0.11.0_BUILD_4.md); historical build-3 evidence
remains in the earlier audit.

See [Release Process](docs/RELEASE.md) for the local process and the GitHub
runner, environment, variable, secret, and source-protection prerequisites.
The latest verification record is
[Build 4 Readiness](docs/AUDIT_0.11.0_BUILD_4.md).

## License

[MIT](LICENSE)
