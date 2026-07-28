# Reframer first-class remediation mission

Mission ID: `reframer-first-class-20260728`

## Goal

Implement the complete remediation plan from the 2026-07-28 end-to-end audit and make Reframer a truthful, reliable, accessible, and production-ready macOS reference-video tool.

## Success criteria

- All advertised keyboard, global, mouse, scroll, menu, lock, and customization behavior has one canonical implementation and passes state-matrix tests.
- Pointer routing, loading, playback, frame stepping, scrubbing, filters, EOF, media errors, and persistence are deterministic.
- Toolbar, panels, overlays, window movement, always-on-top, multi-display recovery, keyboard access, VoiceOver, and Reduce Motion behavior are complete.
- README, Help, DocC, menus, settings, supported formats, version, minimum OS, and tests agree with implementation.
- Debug and Release builds, unit tests, static analysis, UI tests, archive, signing/notarization checks, and bundle-manifest validation are green or have an explicit environment-only blocker with a repeatable recovery procedure.
- The final app bundle contains only intended runtime resources.

## Roster and owned worktrees

| Track | Branch | Worktree | Ownership |
|---|---|---|---|
| Playback correctness | `codex/reframer-playback` | `/private/tmp/reframer-remediation-20260728/playback` | `VideoView`, `VideoState`, formats, filter/playback tests |
| Shortcut platform | `codex/reframer-shortcuts` | `/private/tmp/reframer-remediation-20260728/shortcuts` | shortcut registry/routing/customization, menus, shortcut tests |
| UX and accessibility | `codex/reframer-ux` | `/private/tmp/reframer-remediation-20260728/ux` | edge hit testing, toolbar/filter/drop-zone accessibility and layout |
| Integration and release | `main` | `/Users/ivg/github/reframer` | documentation contract, CI, metadata, packaging, window integration, merge review |

## Worker policy

- Each worker edits only its owned worktree and commits an atomic reviewed slice.
- Workers do not revert unrelated changes.
- The integration owner reviews every diff before cherry-picking.
- Cross-cutting AppDelegate/window changes are integrated on `main` after shortcut and UX slices land.

## Validation commands

```bash
xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -configuration Debug -derivedDataPath /private/tmp/reframer-final-derived -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -configuration Release -derivedDataPath /private/tmp/reframer-final-derived -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -configuration Debug -derivedDataPath /private/tmp/reframer-final-derived -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ReframerTests
xcodebuild -project Reframer/Reframer.xcodeproj -scheme Reframer -configuration Debug -derivedDataPath /private/tmp/reframer-final-derived -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO analyze
xcrun ibtool --warnings --errors --notices --compile /private/tmp/Reframer-ControlBar.nib Reframer/Reframer/Resources/ControlBar.xib
```

UI automation must run on a host where Xcode automation mode and required Input Monitoring/Accessibility permissions are enabled.

## Integration queue

- [ ] Playback worker commit reviewed and integrated
- [ ] Shortcut worker commit reviewed and integrated
- [x] UX/accessibility implementation reviewed and integrated
- [ ] Cross-cutting window and permission UX integrated
- [x] Product contract and user-facing documentation aligned
- [x] CI/release/security/bundle pipeline completed
- [ ] Full validation completed
- [ ] Final mission status recorded
