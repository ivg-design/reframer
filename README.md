# Reframer

Reframer is a native macOS video-reference overlay for animation, motion,
editing, and visual comparison work. It keeps a local video above your
workspace, gives you precise frame navigation, and can become click-through
while you work in the app underneath.

## What it does

- Loads local `.mp4`, `.m4v`, and `.mov` files through AVFoundation
- Steps from one decoded video sample to the next, including fractional-rate
  and variable-timing media
- Plays, pauses, scrubs, zooms, pans, filters, mutes, and adjusts opacity
- Persists opacity, volume, window placement, filter settings, and customized
  shortcuts
- Locks into a click-through overlay
- Supports guarded global frame stepping while a video is loaded and the
  overlay is locked
- Registers only the configured global chords with macOS; it never monitors
  general keyboard input
- Exposes keyboard and VoiceOver names, values, state, and actions

Reframer does not stream media or download executable components. A file whose
container is accepted can still be rejected when macOS cannot decode its video
track; the app reports that failure instead of claiming the load succeeded.

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
| Help and shortcut settings | H |

The frame-step chords work outside Reframer only when a video is loaded and
lock mode is enabled. Global shortcuts use privacy-safe registered hot keys and
require neither Accessibility nor Input Monitoring permission. Registration
conflicts are reported in Shortcut Settings with a retry action. Defaults can
be changed or disabled there.

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

The normal CI suite builds Debug and Release, runs static analysis, validates
the product and bundle contracts, builds DocC, and runs unit tests. The UI suite
runs separately on a logged-in, pre-authorized macOS runner.

## Release

Developer ID signing and notarization are handled by
[`scripts/package_release.sh`](scripts/package_release.sh). The script refuses
dirty sources, validates the universal app bundle, submits it for
notarization, staples the ticket, runs Gatekeeper assessment, and packages the
result.

See [Release Process](docs/RELEASE.md).

## License

[MIT](LICENSE)
