# Reframer feature verification

Feature claims use four distinct evidence classes. A source build is not runtime
evidence, a unit test is not an AppKit interaction, and an XCUITest that only
finds an element is not proof of the action behind it.

## Automated quality gates

| Gate | What a passing result proves | What it does not prove |
|---|---|---|
| `scripts/validate_repository.sh` | Metadata, public-doc, project, scheme, XIB, resource, and workflow invariants match the repository contract | Runtime behavior |
| Debug and Release builds | All production sources and resources compile and link in both configurations | A user can complete a workflow |
| `xcodebuild analyze` | Xcode static analysis reports no blocking issue | Absence of every runtime defect |
| `TEST_SCOPE=unit scripts/runner_test.sh` | Deterministic model and AppKit contract tests pass | WindowServer event routing, visual output, or another-app shortcuts |
| `xcodebuild docbuild` | DocC compiles; bundle validation separately checks Apple Help packaging | Documentation accuracy beyond the validated contract |
| `scripts/validate_bundle.sh` | The unsigned bundle has the expected version, deployment target, architecture, help book, resources, and privacy metadata | Developer ID trust, notarization, or Gatekeeper acceptance |
| Release packaging workflow | The exact artifact passed signing verification, notarization, stapling, and Gatekeeper assessment | Behavior not exercised by the preceding test jobs |

`build-for-testing` is a compile gate for both test targets. It is not recorded
as a UI-test pass unless `xcodebuild test` executes the tests and produces a
successful result bundle.

## Deterministic unit evidence

The unit target currently proves:

- MP4, M4V, and MOV are the only advertised extensions and content types, and
  preflight accepts a known playable fixture while rejecting a missing file,
  corrupt data with a supported extension, and a valid audio-only MP4.
- Frame lookup uses presentation timestamps. Packaged media exercises exact
  23.976, 29.97, 59.94, and 60.00 fps sample indexing plus a real
  variable-frame-rate fixture with irregular intervals. An in-memory table
  covers additional variable timing, while the estimated-timeline tests cover
  fractional-rate fallback.
- First/last clamping, repeated generations, 1/10-frame direction, rapid burst
  accumulation, preview cancellation, structured indexing cancellation, load
  replacement, and unload-during-load are deterministic checks.
- Playback, scrub, zoom, opacity, mute, filter, and persistence state
  transitions obey their model contracts.
- Shortcut defaults, local/global scope, 1/10/100 multipliers, repeat policy,
  collision/reserved-key rejection, migration, clear/disable/re-enable, and
  persistence resolve to typed commands. The exact Carbon registration plan,
  lock-only versus actionable-frame registration lifecycle, AppKit-to-Carbon
  modifier mapping, conflict/retry state, focused-control ownership, and
  active-versus-inactive dispatch policy also have unit coverage.
- Window recovery, toolbar reservation, attached-panel placement, and invalid
  geometry handling are checked as pure geometry.
- Drop-zone actionability, quick-filter menu contents, advanced-filter control
  naming/focus, lock-aware drag-handle state, status text, and pointer-transparent
  overlays are checked through AppKit objects.

These checks do not prove that macOS delivered a physical key, pointer, drag,
display, accessibility, or workspace event to the running app.

## XCUITest evidence contract

The serial UI target launches a new app process with an isolated preference
suite for every test. It opens its fixture through Launch Services, exercising
the same user-selected read-only sandbox-extension path as Finder's Open With
flow.

Current evidence status (2026-07-28): `build-for-testing` compiled the complete
unit and UI targets, but the UI tests were not executed in this remediation
session. The runner acknowledgment was not present, so
`scripts/ui_test_preflight.sh` correctly exited 77; a separate live-app attempt
could not start because the macOS desktop was locked. The bullets below
therefore describe what a passing execution will prove, not results already
recorded:

- the empty state exposes a labeled, enabled Open video action;
- clicking the empty state and pressing Command-O each present a cancellable
  system file picker, and Cancel restores the empty state;
- H presents the labeled Shortcut Settings group and its labeled Close action
  dismisses it;
- the Launch Services fixture reaches a ready, enabled timeline and exposes
  frame, zoom, and lock status elements;
- Space and the Play button advance frames and return to an observable paused
  state;
- step buttons, frame entry, and timeline adjustment update the frame field;
- while Reframer is active, Command-Page Down, Command-Shift-Page Down,
  Command-Page Up, and Command-Shift-Page Up exercise both directions and the
  one/ten-sample factors;
- zoom entry, arrow increments, 0, and R update the zoom field;
- lock input updates the lock value and zoom-control enabled state;
- opacity entry and arrow increments update the field;
- selecting Invert disables its parameter control and shows `On`, while
  Brightness re-enables the adjustable control;
- mute/unmute updates the exposed audio state and restores the prior slider
  value;
- F and Command-? open their named panels, and Escape closes each one;
- Space activates a focused Quick Filter button or filter switch without also
  toggling playback;
- rebinding Play/Pause from Space to J removes the old chord, activates the new
  chord, survives relaunch, can be disabled, and remains disabled after another
  relaunch;
- while Finder is active, all four frame-step variants dispatch exactly once
  in both directions and at one/ten-sample factors while loaded and locked;
- the actionable state reports five registered defaults (lock plus four frame
  variants), global Command-Shift-L unlocks, the unlocked state reports only
  the lock registration, and Command-Page Down is neither delivered to
  Reframer nor swallowed then.

`ZoomScreenshotTest` always asserts the 100% to 200% zoom transition.
`UITEST_SCREENSHOTS=1` only adds retained PNG evidence; omitting that variable
does not skip the behavioral assertions.

Run the target only in a logged-in session whose operator has acknowledged
Xcode UI automation:

```bash
REFRAMER_UI_RUNNER_AUTHORIZED=1 \
TEST_SCOPE=ui \
scripts/runner_test.sh
```

The preflight never edits TCC databases, restarts privacy services, strips
provenance, or re-signs a test product. Global shortcut delivery uses registered
system hotkeys and does not require Accessibility or Input Monitoring permission.

## Live macOS evidence still required

The following claims need an observed live pass because the current automated
suite does not measure their result:

- selecting a real file in the picker and Finder Open With;
- valid/invalid file drag-and-drop feedback and loading;
- video-surface pointer pan at 1x and above, including reversal across the drag
  origin;
- toolbar drag-handle movement, lock suppression, and visible lock/status HUD;
- resize behavior at minimum size and toolbar attachment while moving;
- Always on Top, click-through, and recovery/unlock from another app;
- an actual registration conflict with another owner and the visible retry
  recovery path;
- multi-display placement, display removal, and visible-frame clamping;
- keyboard-only traversal and focus restoration for shortcut, filter, and
  documentation panels;
- VoiceOver announcements/actions, Increase Contrast/Reduce Transparency, and
  Reduce Motion;
- visual filter correctness, composited opacity, and VFR audiovisual playback;
- preferences after termination and relaunch.

Record the macOS version, hardware, app commit, fixture, starting state,
interaction, observed result, and screenshot/screen recording for each live
claim. Do not mark a row passed from a build log or from an element-existence
assertion.

The release workflow requires both the deterministic quality job and an
executed self-hosted UI job before signing and notarization. No Developer ID
distribution signing, notarization submission, staple, or Gatekeeper
assessment ran during this remediation session. The live checks above remain
release evidence that must be attached to a future candidate when their
behavior changes.
