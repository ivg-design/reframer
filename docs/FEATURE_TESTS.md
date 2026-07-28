# Reframer feature verification

Shipping claims must have deterministic automated coverage where possible and
a named interactive check where macOS UI automation is involved.

## Required automated gates

| Area | Required evidence |
|---|---|
| Repository | Product metadata, public docs, project, scheme, XIB, and unsafe-runner checks pass |
| Build | Clean Debug and Release builds for the explicit Xcode project |
| Static quality | `xcodebuild analyze` succeeds |
| Unit suite | All model, command, format, playback, filter, persistence, and accessibility-contract tests pass |
| Documentation | DocC builds and Apple Help is present in the built bundle |
| Bundle | Only allowlisted runtime resources and sandbox entitlements; version 0.10.0; build integer; macOS 15.0 minimum |
| Release | Universal binary, strict code-sign verification, successful notarization/stapling, successful Gatekeeper assessment |

## Playback matrix

- 30 fps and 60 fps constant-rate fixtures
- Fractional-rate fixture
- Variable-timing fixture
- First and last sample clamping
- One-frame and 10-frame steps in both directions
- Rapid alternating and repeated step bursts
- Preview scrub coalescing and exact final seek
- Load A immediately superseded by load B
- Seek immediately superseded by load
- End-of-file transition and replay
- Missing track, unsupported track, corrupt file, and cancelled load
- Filter replacement and cancellation during playback and seek

The current repository fixtures cover constant-rate media. Fractional and
variable-timing fixture generation is part of the deterministic test target and
must remain offline.

## Shortcut state matrix

Every command is checked across:

- app active and inactive
- video unloaded and loaded
- overlay unlocked and locked
- ordinary focus, text editing, modal panel, and shortcut recording
- key repeat allowed and suppressed
- default, rebound, cleared, disabled, persisted, and migrated settings

The expected global defaults are Command-Page Down for forward,
Command-Page Up for backward, and Command-Shift-L for lock. Stepping outside
the app is rejected unless a video is loaded and the overlay is locked. One
physical event must produce exactly one command.

Unit coverage also verifies the exact registered-hot-key descriptor plan,
AppKit-to-Carbon modifier mapping, registration status/recovery model, and the
focused-control ownership policy. Global shortcut tests must not depend on
Accessibility or Input Monitoring permission.

## Interactive macOS suite

The serial UI suite runs on a logged-in self-hosted runner. A person grants
the runner normal UI-automation authorization once and sets
`REFRAMER_UI_RUNNER_AUTHORIZED=1`. Scripts must not alter privacy databases,
restart privacy services, remove provenance, or re-sign test products.

The suite verifies:

- exact-once registered lock and frame-step delivery while Finder is active,
  plus the loaded-and-locked global guard
- open picker, click-to-open empty state, and drag/drop
- load, play, pause, step, scrub, filter, opacity, mute, zoom, and pan
- resize and toolbar behavior at minimum size
- move, Always on Top, lock, click-through, unlock, and multi-display clamping
- keyboard-only traversal and panel focus return
- VoiceOver roles, labels, values, state, and actions
- Reduce Motion presentation
- persistence after terminate and relaunch

Run unit tests with `scripts/runner_test.sh`. Run the full serial suite on an
authorized runner with `TEST_SCOPE=all scripts/runner_test.sh`.
