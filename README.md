# Reframer

Reframer is a native macOS video-reference overlay for animation, motion,
editing, and visual comparison work. It keeps a local video above your
workspace, gives you precise frame navigation, and can become click-through
while you work in the app underneath.

## What it does

- Loads local `.mp4`, `.m4v`, and `.mov` files through AVFoundation
- Indexes decoded presentation samples for exact fractional-rate and
  variable-timing navigation, with a clearly labeled bounded estimate when
  exact indexing is unavailable
- Plays, pauses, scrubs, zooms, pans, filters, mutes, and adjusts opacity
- Persists opacity, volume, window placement, filter settings, and customized
  shortcuts
- Locks into a click-through overlay
- Keeps the enabled global lock chord available from any video or lock state
- Registers global frame-step chords only while a video is loaded, the overlay
  is locked, and exact or estimated sample navigation is available
- Never monitors general keyboard input from other apps or reserves inactive
  global frame-step chords
- Exposes keyboard and VoiceOver names, values, state, and actions, including
  complete slider ranges/orientation and independently reachable ready-state
  badges

Reframer does not stream media or download executable components. A file whose
container is accepted can still be rejected when macOS cannot decode a usable
video track; the app reports that failure instead of claiming the load
succeeded. When a file contains multiple video tracks, the enabled usable track
selected for playback and Core Image filtering is also the source of
dimensions and frame navigation.

## Requirements

- macOS 15.0 or later
- Xcode 16 or later to build from source

## Essential controls

| Action | Default |
|---|---|
| Open video | Command-O |
| Play or pause | Space |
| Step forward | Command-Page Down |
| Step backward | Command-Page Up |
| Step 10 frames | Add Shift |
| Pan | Arrow keys |
| Pan 10 / 100 points | Shift / Command-Shift + Arrow |
| Zoom / fine zoom | Shift / Command-Shift + Scroll |
| Reset zoom / view | 0 / R |
| Toggle lock locally / globally | L / Command-Shift-L |
| Filters | F |
| Shortcut settings | H |
| Documentation | Command-? |

The enabled global lock chord stays registered during normal operation. The
four frame-step variants are registered only when a loaded, locked video has
exact or estimated sample navigation, so those key combinations remain
available to other apps in every other state. Global shortcuts use privacy-safe
registered hot keys and require neither Accessibility nor Input Monitoring
permission. Registration conflicts are reported in Shortcut Settings with a
retry action. Defaults can be changed or disabled there.

Reframer runs in App Sandbox and receives read-only access only to videos the
user explicitly opens or drops.

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

scripts/runner_test.sh
```

The normal CI suite builds Debug and universal Release, runs static analysis,
validates the product and bundle contracts, builds DocC, and runs unit tests.
The UI suite runs separately in an unlocked, logged-in macOS session whose
operator has explicitly acknowledged Xcode UI automation.

## Release

Developer ID signing and notarization are handled by
[`scripts/package_release.sh`](scripts/package_release.sh). The script refuses
dirty sources, validates the universal app bundle, submits it for
notarization, staples the ticket, runs Gatekeeper assessment, and packages the
result.

Those are external release-acceptance gates, not results of the remediation
run. No Developer ID distribution signing, Apple notarization submission,
stapling, or Gatekeeper assessment has been recorded without the required Apple
credentials.

See [Release Process](docs/RELEASE.md) for the local process and the GitHub
runner, environment, variable, secret, and source-protection prerequisites.
The latest verification record is
[Audit and Release Readiness](docs/AUDIT_2026-07-28.md).

## License

[MIT](LICENSE)
