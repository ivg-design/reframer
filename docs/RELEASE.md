# Release process

Reframer releases are traceable to a clean tagged commit. They are not claimed
to be bit-for-bit reproducible: Xcode and the source-stamp phase record build
environment and time metadata.

An unsigned or ad hoc signed archive is source-candidate validation evidence,
not a distribution-ready artifact. A published build must pass the interactive
UI gate plus Developer ID signing, notarization, stapling, and Gatekeeper
assessment. Apple distribution acceptance does not prove window interaction,
click-through behavior, or nonblank Help content; those remain explicit live
gates for every candidate.

## Local Apple credentials

Local packaging requires:

- a Developer ID Application certificate;
- the Apple Developer team identifier;
- a `notarytool` keychain profile;
- a YouTube Data API key with the YouTube Data API enabled and appropriate API,
  quota, and monitoring restrictions.

On the maintainer machine documented for this project, use the existing
non-secret identity, team, and keychain-profile names:

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Ilya Gusinski (7S422NVLUK)'
export DEVELOPMENT_TEAM='7S422NVLUK'
export NOTARY_PROFILE='notary'
export REFRAMER_YOUTUBE_DATA_API_KEY='<release secret>'
```

Confirm the stored credentials are available without creating or replacing
them, then run Reframer's authoritative packager from a clean worktree:

```bash
xcrun notarytool history --keychain-profile notary
security find-identity -v -p codesigning
scripts/validate_repository.sh
scripts/package_release.sh
```

## GitHub release prerequisites

The workflow references these controls; GitHub does not create their security
policy for this repository automatically.

| Scope | Required configuration |
|---|---|
| Self-hosted runner | An isolated, unlocked macOS account with a current Actions Runner compatible with Node 24 actions, labels `self-hosted`, `macOS`, and `reframer-ui`, and no personal data or release credentials |
| Repository variable | `REFRAMER_UI_RUNNER_AUTHORIZED=1` after the runner operator has approved Xcode UI automation |
| Protected environment | `release`, with required reviewers and deployment branch/tag restrictions |
| Environment secrets | `DEVELOPER_ID_CERTIFICATE_BASE64`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `RELEASE_KEYCHAIN_PASSWORD`, `DEVELOPER_ID_APPLICATION`, `DEVELOPMENT_TEAM`, `NOTARY_API_KEY_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, and `REFRAMER_YOUTUBE_DATA_API_KEY` |
| Main protection | Require the CI workflow and reviewed changes on `main` |
| Tag protection | Limit creation of `v*` release tags to authorized maintainers |
| Actions policy | Restrict allowed actions and require immutable full-SHA references in repository policy as defense in depth |
| Security features | Enable Dependabot security updates and private vulnerability reporting |

The self-hosted PR workflow accepts same-repository pull requests only. Its
checkout token is read-only and is not persisted. Signing secrets belong only
to the protected hosted release job, never the UI runner.

## Version and source gate

Before creating a tag:

1. keep `MARKETING_VERSION`, the Help version, and
   `docs/product-contract.json` aligned;
2. use one numeric `CURRENT_PROJECT_VERSION`, increment it for every newly
   notarized candidate, and never reuse the same marketing-version/build pair
   for different content;
3. replace `Unreleased` in the matching changelog heading with the release
   date;
4. confirm the candidate commit is on protected `main`;
5. complete the unit, UI, live-smoke, accessibility, and Apple credential
   gates;
6. retain the exact FFmpeg/libvpx corresponding source plus Reframer
   source/object/relink materials and build scripts for at least three years
   after the final distribution covered by the bundled LGPL offer.

Use an exact semantic-version tag such as `v0.11.0`. The workflow rejects a tag
whose version differs from Xcode, whose changelog entry is not dated, or whose
commit is not an ancestor of `origin/main`. The release job rechecks its exact
checkout, and publication re-resolves the remote tag to the immutable workflow
event commit. A manual dispatch must also use a commit on `origin/main`; it may
package a still-Unreleased candidate but does not publish a GitHub release
unless its selected ref is a tag. Do not create a tag merely to test an
unconfigured release workflow; use `workflow_dispatch` after supplying its
version input.

## Documentation and Help sync

After changing Apple Help HTML, regenerate its CoreSpotlight index before
validation:

```bash
hiutil -I corespotlight -C -ag -s en -l en_US \
  -f Reframer/Reframer/Reframer.help/Contents/Resources/en.lproj/search.cshelpindex \
  Reframer/Reframer/Reframer.help/Contents/Resources/en.lproj

scripts/validate_repository.sh
```

The repository validator rebuilds the index in a temporary directory and
compares its searchable records, so stale Help content cannot pass merely
because a compiled index file exists.

The shipping documentation window must also be exercised from the candidate
bundle. It renders those bundled HTML pages with native AppKit, must display
known nonblank text, and must not launch WebKit or fetch network content.
Allowlisted YouTube/Google policy links open in the system browser. The app's
network entitlement belongs to YouTube playback, not Help.

## Packaging guarantees

The packager:

1. refuses a dirty worktree, version mismatch, or missing/unexpanded
   `REFRAMER_YOUTUBE_DATA_API_KEY`; local packaging also requires
   `main` at the locally fetched `origin/main` commit (the GitHub workflow has
   its separate immutable event-commit checks), then runs the complete
   repository/product/Help/helper-provenance gate before archiving;
2. archives a universal arm64/x86_64 Release build with Hardened Runtime,
   injects the Data API key as the Xcode `YOUTUBE_DATA_API_KEY` setting through
   a mode-0600 temporary xcconfig, redacts the value from build output, never
   writes it to source, and signs the nested `reframer-ffmpeg` helper,
   keeping DerivedData inside its scoped temporary work directory and
   unregistering intermediate Reframer apps before cleanup;
3. validates bundle metadata against the current project version and numeric
   build, requires a clean source stamp for release artifacts, checks both
   app and helper slices’ deployment target, and checks the exact
   Contents/signature/executable/helper/runtime/Help/license allowlists,
   absence of symlinks, a configured non-placeholder Data API key, the app
   entitlement allowlist (App Sandbox, user-selected read-only, and network
   client), and helper allowlist (App Sandbox and inherited sandbox); it also
   validates both helper slices' normalized FFmpeg feature surface, proves the
   recorded canonical SHA, and compares packaged versus canonical helper code
   after deterministically ad hoc re-signing temporary copies with the exact
   helper entitlements and identifier;
4. verifies Developer ID signatures and exact embedded app/helper entitlements;
5. submits to Apple, requires an `Accepted` result, and records the submission
   JSON and ID;
6. staples and validates the ticket, re-verifies the signature, and runs
   Gatekeeper assessment;
7. validates the post-staple bundle contract, extracts the final ZIP, and
   repeats bundle, signature, ticket, and Gatekeeper verification;
8. writes:
   - `dist/Reframer-<version>-macOS.zip`;
   - `dist/Reframer-<version>-notarization.json`;
   - `dist/SHA256SUMS.txt`.

On a tag, the GitHub workflow publishes those exact files only after the hosted
quality job, self-hosted UI job, protected-environment approval, and Apple
verification succeed.

The secret is necessarily embedded in a desktop app and can be extracted from
the built `Info.plist`. API restriction and quota monitoring reduce misuse but
do not make it secret. For a broadly distributed production build, prefer a
narrow backend that performs the per-video Made for Kids preflight and returns
only the authorization decision.

## Final smoke check

This is a foreground, manual gate. XCUITest also launches and foregrounds
Reframer and takes focus; neither becomes a background test because it starts
from Terminal. Do not run UI automation without fresh operator authorization
for that specific run. The background-safe automated command is
`TEST_SCOPE=unit scripts/runner_test.sh`.

On macOS 15.0 or later with no Reframer preferences:

1. verify the checksum, unzip, launch, and confirm Gatekeeper accepts the app;
2. open known MP4/M4V/MOV, AVI, DV, MPEG/transport-stream, and 3GP/3G2
   fixtures that use AVFoundation-decodable codecs and verify first-frame
   rendering;
3. prepare VP8 and VP9 WebM fixtures with alpha and audio; verify transparent
   compositing, playback, exact/estimated frames, filters, cancellation, the
   64 GB safety behavior by deterministic test, and temporary cleanup;
4. play, pause, step both directions, step 10, scrub, and replay after end;
5. zoom, pan, filter, change opacity, mute, and move the unlocked overlay with
   its grip;
6. use macOS or Mosaic to move and resize the unlocked overlay, confirming the
   video and control bar remain one integral externally managed window; verify
   one 48-point control row at 920 points and wider, two rows totaling 96
   points below 920 through the 640-point minimum, and every control remains
   visible and accessibility-reachable;
7. open Shortcut Settings, resize it from 700×520 through its 780×1020
   preferred size toward 1100×1100, confirm one shared five-column alignment,
   inspect all shortcuts at the preferred height, test compact-height
   scrolling, row-major focus, and remembered size;
8. launch at the preferred 1,060-point width, toggle Always on Top When
   Unlocked, relaunch, and confirm the saved
   unlocked-state level;
9. make the configured global Lock/Unlock chord unavailable and confirm lock
   is refused with recovery guidance; after locking with the chord registered,
   remove or suspend that registration and confirm Reframer automatically
   unlocks and reports recovery;
10. turn Always on Top When Unlocked off, lock, and confirm the complete overlay
   uses the public status-bar window tier above all foreground ordinary
   application windows, including normal, floating, modal, and utility
   windows, ignores pointer input over both video and controls, and cannot be
   moved or resized;
11. click a known interactive target beneath both overlay regions to prove
   pointer delivery, use Command-Page Down and Command-Page Up from that app,
   then unlock with Command-Shift-L and confirm the saved unlocked window level
   returns;
12. confirm system pop-up menus, drag UI, the screen saver, and
   assistive-technology UI retain precedence over the locked overlay;
13. confirm an unlocked frame chord remains observable in the foreground app;
14. open Reframer Documentation from the Help menu and with Command-?, verify
    known bundled content is visible in the native view, navigate a link and
    scroll by keyboard, then close with Escape;
15. use Open YouTube Video with a valid API key: review and accept consent,
    prove the Made for Kids preflight succeeds before the player appears, then
    test play/pause, time scrub, mute, volume, adaptive quality, standard
    controls/links/settings/fullscreen, error handling, hidden/occluded pause,
    automatic unlock before preflight, disabled click-through Lock, and Always
    on Top When Unlocked. Confirm required controls, captions, settings,
    fullscreen, and links remain interactive; confirm no autoplay and that
    exact frames, zoom/pan, opacity, and filters are unavailable;
16. confirm Shortcut Settings reports registration without an Accessibility or
    Input Monitoring prompt;
17. relaunch and verify persisted preferences and window geometry;
18. complete keyboard, VoiceOver, Increase Contrast, Reduce Transparency,
    Reduce Motion, and multi-display checks.

Record the commit, version/build, macOS version, architecture, UI/live results,
notarization submission ID, and artifact checksum in the GitHub release.
Candidate-specific local evidence is tracked in
[Build 4 Readiness](AUDIT_0.11.0_BUILD_4.md). Historical build-3 evidence
remains in [the prior audit](AUDIT_2026-07-28.md).
