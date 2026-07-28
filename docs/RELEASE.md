# Release process

Reframer releases are reproducible from a clean tagged commit.

## Required Apple credentials

- Developer ID Application certificate
- Apple Developer team identifier
- `notarytool` keychain profile

Configure these environment variables without storing credentials in the
repository:

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: …'
export DEVELOPMENT_TEAM='…'
export NOTARY_PROFILE='reframer-release'
```

Then run:

```bash
scripts/validate_repository.sh
scripts/package_release.sh
```

The packager:

1. refuses a dirty worktree or version mismatch;
2. archives a universal Release build with Hardened Runtime;
3. validates bundle metadata and resource allowlisting;
4. verifies the Developer ID signature;
5. submits the app to Apple, waits for notarization, and staples the ticket;
6. validates the staple and runs Gatekeeper assessment;
7. writes `dist/Reframer-<version>-macOS.zip`.

The GitHub release workflow performs the same process using repository secrets.
It publishes only after every validation and Apple verification succeeds.

## Final smoke check

On a macOS 15.0 or later machine with no Reframer preferences:

1. unzip, launch, and confirm Gatekeeper accepts the app;
2. open a known MP4 fixture and verify first-frame rendering;
3. play, pause, step both directions, step 10, scrub, and replay after end;
4. zoom, pan, filter, change opacity, mute, move, resize, and toggle Always on
   Top;
5. lock, click through, use Command-Page Down and Command-Page Up from another
   app, then unlock with Command-Shift-L;
6. relaunch and verify persisted preferences;
7. complete a keyboard and VoiceOver pass.

Record the commit, version/build, macOS version, hardware architecture, test
result, notarization submission ID, and artifact checksum in the GitHub
release.
