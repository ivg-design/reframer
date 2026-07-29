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
- Presents the video and control bar as one canonical overlay window, so
  macOS and window managers such as Mosaic move and resize the complete
  unlocked overlay
- Uses the preferred 1,060-point width with one 48-point control row for its
  initial layout and restores saved geometry thereafter; below 920 points the
  same controls reflow into two rows totaling 96 points, with every control
  still visible and accessibility-reachable down to the 640-point minimum width
- Locks the complete overlay at macOS's public status-bar window tier, above
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
| Advanced filters | F |
| Shortcut settings | H |
| Documentation | Command-? |

The enabled global lock chord stays registered during normal operation. The
four frame-step variants are registered only when a loaded, locked video has
exact or estimated sample navigation, so those key combinations remain
available to other apps in every other state. Global shortcuts use privacy-safe
registered hot keys and require neither Accessibility nor Input Monitoring
permission. Registration conflicts are reported in Shortcut Settings with a
retry action. Defaults can be changed or disabled there. Because every pointer
event passes through the complete locked overlay, use the enabled global lock
chord—Command-Shift-L by default—to unlock it from the app underneath.
Reframer will not lock unless that exact configured chord is registered. If
registration later disappears, conflicts, is suspended during shortcut
recording, or global shortcuts are disabled, Reframer immediately unlocks and
reports how to restore recovery before locking again.
Critical system-owned UI still takes precedence over the overlay, including
pop-up menus, drag UI, the screen saver, and assistive-technology windows.

Reframer runs in App Sandbox and receives read-only access only to videos the
user explicitly opens or drops. Its documentation window renders the bundled
Help pages with native AppKit, remains fully offline in the sandbox, and does
not require a network entitlement.

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

## Release

Developer ID signing and notarization are handled by
[`scripts/package_release.sh`](scripts/package_release.sh). The script refuses
dirty sources, validates the universal app bundle, submits it for
notarization, staples and revalidates the ticket-bearing bundle, runs
Gatekeeper assessment, packages the result, then extracts and rechecks the
final ZIP. Release DerivedData remains inside a scoped temporary directory;
temporary app registrations are removed during cleanup so packaging does not
seed older Reframer builds into LaunchServices or Spotlight.
Local packaging also refuses source that is not clean, on `main`, and equal to
the locally fetched `origin/main`.

The audit records the historical build-1 and build-2 review runs, the packaging
gap build 1 exposed, and the live product defects found after build 2 passed
Apple's distribution checks. The build-3 source candidate has completed its
background unit and repository validation; foreground/manual interaction and
Apple distribution gates remain separately recorded until they are performed.
Only evidence emitted for a particular artifact proves that artifact. A local
review run does not create a version tag, GitHub release, or published
distribution.

See [Release Process](docs/RELEASE.md) for the local process and the GitHub
runner, environment, variable, secret, and source-protection prerequisites.
The latest verification record is
[Audit and Release Readiness](docs/AUDIT_2026-07-28.md).

## License

[MIT](LICENSE)
