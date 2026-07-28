# Historical Reframer first-class remediation mission

This completed mission-control record preserves implementation provenance,
including temporary branches and worktrees. Current behavior and evidence live
in the root README, product contract, feature verification, and dated audit.

Mission ID: `reframer-first-class-20260728`

## Goal

Implement the complete remediation plan from the 2026-07-28 end-to-end audit and make Reframer a truthful, reliable, accessible, and production-ready macOS reference-video tool.

Implementation status: complete. Release acceptance still requires the
explicitly listed UI-session and Apple-credential gates below.

## Success criteria

- All advertised keyboard, global, mouse, scroll, menu, lock, and customization behavior has one canonical implementation and passes state-matrix tests.
- The enabled global lock chord remains registered during normal operation;
  frame-step chords exist only while a loaded, locked video has exact or
  estimated sample navigation and therefore do not swallow keys otherwise.
- Pointer routing, loading, playback, frame stepping, scrubbing, filters, EOF, media errors, and persistence are deterministic.
- Toolbar, panels, overlays, window movement, always-on-top, multi-display recovery, keyboard access, VoiceOver, and Reduce Motion behavior are complete.
- README, Help, DocC, menus, settings, supported formats, version, minimum OS, and tests agree with implementation.
- Debug and Release builds, unit tests, static analysis, UI tests, archive, signing/notarization checks, and bundle-manifest validation are green or have an explicit environment-only blocker with a repeatable recovery procedure.
- The final app bundle contains only intended runtime resources.

## Roster and owned worktrees

| Track | Branch | Worktree | Ownership |
|---|---|---|---|
| Playback correctness | `codex/reframer-playback` | temporary isolated worktree | `VideoView`, `VideoState`, formats, filter/playback tests |
| Shortcut platform | `codex/reframer-shortcuts` | temporary isolated worktree | shortcut registry/routing/customization, menus, shortcut tests |
| UX and accessibility | `codex/reframer-ux` | temporary isolated worktree | edge hit testing, toolbar/filter/drop-zone accessibility and layout |
| Integration and release | `main` | repository root | documentation contract, CI, metadata, packaging, window integration, merge review |

## Worker policy

- Each worker edits only its owned worktree and commits an atomic reviewed slice.
- Workers do not revert unrelated changes.
- The integration owner reviews every diff before cherry-picking.
- Cross-cutting AppDelegate/window changes are integrated on `main` after shortcut and UX slices land.

## Validation commands

```bash
scripts/validate_repository.sh
TEST_SCOPE=unit scripts/runner_test.sh

xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -configuration Debug -derivedDataPath "$TMPDIR/Reframer-Debug" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -configuration Release -derivedDataPath "$TMPDIR/Reframer-Release" -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -configuration Debug -derivedDataPath "$TMPDIR/Reframer-Analyze" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO analyze
xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -derivedDataPath "$TMPDIR/Reframer-Docs" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO docbuild
xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -derivedDataPath "$TMPDIR/Reframer-Tests" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build-for-testing
xcrun ibtool --warnings --errors --notices --compile "$TMPDIR/Reframer-ControlBar.nib" Reframer/Reframer/Resources/ControlBar.xib
```

UI automation must run in a logged-in macOS session whose operator has
explicitly acknowledged Xcode UI automation by setting
`REFRAMER_UI_RUNNER_AUTHORIZED=1`. Reframer's registered-hot-key implementation
requires neither Input Monitoring nor Accessibility permission, and the test
preflight does not modify TCC.

## Integration queue

- [x] Playback correctness implementation reviewed and integrated
- [x] Shortcut implementation reviewed and integrated
- [x] UX/accessibility implementation reviewed and integrated
- [x] Cross-cutting window and registered-hot-key lifecycle integrated
- [x] Product contract and user-facing documentation aligned
- [x] CI/release/security/bundle pipeline completed
- [x] Full local non-UI validation completed
- [x] UI test targets compiled with `build-for-testing`
- [ ] UI suite executed on an acknowledged, unlocked macOS automation session
- [ ] Live interaction/accessibility evidence recorded
- [ ] Developer ID distribution signing, notarization, stapling, and Gatekeeper assessment completed with Apple credentials
- [x] Final implementation status recorded

## Recorded validation and external gates

The latest integrated-state validation passed all 162 deterministic unit tests,
Debug build, universal Release build, static analysis, DocC build, repository
and product-contract validators, XIB validation with zero diagnostics,
built-bundle validation, and unsigned universal archive validation. The unit
and UI targets also compiled with `build-for-testing`.

These results do not constitute an executed UI pass or an Apple distribution
release. In this session, UI preflight exited 77 because runner authorization
was not acknowledged, and a live-app attempt was blocked by a locked desktop.
Apple distribution credentials were unavailable, so Developer ID signing,
notarization, stapling, and Gatekeeper acceptance were not run. The mission is
implementation-complete and remains release-candidate-pending until those
external evidence gates pass.
