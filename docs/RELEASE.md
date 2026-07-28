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
- a `notarytool` keychain profile.

Configure them outside the repository:

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: …'
export DEVELOPMENT_TEAM='…'
export NOTARY_PROFILE='reframer-release'
```

Then run from a clean worktree:

```bash
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
| Environment secrets | `DEVELOPER_ID_CERTIFICATE_BASE64`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `RELEASE_KEYCHAIN_PASSWORD`, `DEVELOPER_ID_APPLICATION`, `DEVELOPMENT_TEAM`, `NOTARY_API_KEY_BASE64`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID` |
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
2. use one numeric `CURRENT_PROJECT_VERSION`;
3. replace `Unreleased` in the matching changelog heading with the release
   date;
4. confirm the candidate commit is on protected `main`;
5. complete the unit, UI, live-smoke, accessibility, and Apple credential
   gates.

Use an exact semantic-version tag such as `v0.10.0`. The workflow rejects a tag
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
known nonblank text, and must not require a WebKit helper or network
entitlement.

## Packaging guarantees

The packager:

1. refuses a dirty worktree or version mismatch; local packaging also requires
   `main` at the locally fetched `origin/main` commit (the GitHub workflow has
   its separate immutable event-commit checks);
2. archives a universal arm64/x86_64 Release build with Hardened Runtime,
   keeping DerivedData inside its scoped temporary work directory and
   unregistering intermediate Reframer apps before cleanup;
3. validates bundle metadata against the current project version and numeric
   build, requires a clean source stamp for release artifacts, checks both
   slices’ deployment target, and checks the exact
   Contents/signature/executable/runtime/Help allowlists, absence of symlinks,
   and the source sandbox entitlement allowlist: App Sandbox plus
   user-selected, read-only file access, with no network entitlement;
4. verifies the Developer ID signature and exact embedded release entitlements;
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

## Final smoke check

On macOS 15.0 or later with no Reframer preferences:

1. verify the checksum, unzip, launch, and confirm Gatekeeper accepts the app;
2. open known MP4, M4V, and MOV fixtures and verify first-frame rendering;
3. play, pause, step both directions, step 10, scrub, and replay after end;
4. zoom, pan, filter, change opacity, mute, and move the unlocked overlay with
   its grip;
5. use macOS or Mosaic to move and resize the unlocked overlay, confirming the
   video and control bar remain one integral externally managed window; verify
   one 48-point control row at 920 points and wider, two rows totaling 96
   points below 920 through the 640-point minimum, and every control remains
   visible and accessibility-reachable;
6. launch at the preferred 1,060-point width, toggle Always on Top When
   Unlocked, relaunch, and confirm the saved
   unlocked-state level;
7. make the configured global Lock/Unlock chord unavailable and confirm lock
   is refused with recovery guidance; after locking with the chord registered,
   remove or suspend that registration and confirm Reframer automatically
   unlocks and reports recovery;
8. turn Always on Top When Unlocked off, lock, and confirm the complete overlay
   uses the public status-bar window tier above all foreground ordinary
   application windows, including normal, floating, modal, and utility
   windows, ignores pointer input over both video and controls, and cannot be
   moved or resized;
9. click a known interactive target beneath both overlay regions to prove
   pointer delivery, use Command-Page Down and Command-Page Up from that app,
   then unlock with Command-Shift-L and confirm the saved unlocked window level
   returns;
10. confirm system pop-up menus, drag UI, the screen saver, and
   assistive-technology UI retain precedence over the locked overlay;
11. confirm an unlocked frame chord remains observable in the foreground app;
12. open Reframer Documentation from the Help menu and with Command-?, verify
    known bundled content is visible in the native view, navigate a link and
    scroll by keyboard, then close with Escape;
13. confirm Shortcut Settings reports registration without an Accessibility or
    Input Monitoring prompt;
14. relaunch and verify persisted preferences and window geometry;
15. complete keyboard, VoiceOver, Increase Contrast, Reduce Transparency,
    Reduce Motion, and multi-display checks.

Record the commit, version/build, macOS version, architecture, UI/live results,
notarization submission ID, and artifact checksum in the GitHub release.
Candidate-specific local evidence is tracked in
[Audit and Release Readiness](AUDIT_2026-07-28.md).
