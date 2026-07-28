# Release process

Reframer releases are traceable to a clean tagged commit. They are not claimed
to be bit-for-bit reproducible: Xcode and the source-stamp phase record build
environment and time metadata.

An unsigned or ad hoc signed archive is source-candidate validation evidence,
not a distribution-ready artifact. A published build must pass the interactive
UI gate plus Developer ID signing, notarization, stapling, and Gatekeeper
assessment.

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

## Packaging guarantees

The packager:

1. refuses a dirty worktree or version mismatch;
2. archives a universal arm64/x86_64 Release build with Hardened Runtime;
3. validates bundle metadata, both slices’ deployment target, exact
   Contents/signature/executable/runtime/Help allowlists, absence of symlinks,
   source stamp, and the source sandbox entitlement allowlist;
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
4. zoom, pan, filter, change opacity, mute, move, resize, and toggle Always on
   Top;
5. lock, click through, use Command-Page Down and Command-Page Up from another
   app, then unlock with Command-Shift-L;
6. confirm an unlocked frame chord remains observable in the foreground app;
7. confirm Shortcut Settings reports registration without an Accessibility or
   Input Monitoring prompt;
8. relaunch and verify persisted preferences;
9. complete keyboard, VoiceOver, Increase Contrast, Reduce Transparency,
   Reduce Motion, and multi-display checks.

Record the commit, version/build, macOS version, architecture, UI/live results,
notarization submission ID, and artifact checksum in the GitHub release.
Candidate-specific local evidence is tracked in
[Audit and Release Readiness](AUDIT_2026-07-28.md).
