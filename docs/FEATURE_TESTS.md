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
  preflight accepts a known playable fixture while rejecting a missing file.
- Frame lookup uses presentation timestamps, including an in-memory
  variable-timing table. Packaged media exercises 29.97 and 60 fps sample
  indexing. First/last clamping, repeated generations, 1/10-frame direction,
  and rapid burst accumulation are deterministic model checks.
- Playback, scrub, zoom, opacity, mute, filter, and persistence state
  transitions obey their model contracts.
- Shortcut defaults, local/global scope, 1/10/100 multipliers, repeat policy,
  collision/reserved-key rejection, migration, clear/disable/re-enable, and
  persistence resolve to typed commands. The exact Carbon registration plan,
  AppKit-to-Carbon modifier mapping, conflict/retry state, focused-control
  ownership, and active-versus-inactive dispatch policy also have unit coverage.
- Window recovery, toolbar reservation, attached-panel placement, and invalid
  geometry handling are checked as pure geometry.
- Drop-zone actionability, quick-filter menu contents, advanced-filter control
  naming/focus, lock-aware drag-handle state, status text, and pointer-transparent
  overlays are checked through AppKit objects.

These checks do not prove that macOS delivered a physical key, pointer, drag,
display, accessibility, or workspace event to the running app.

## XCUITest evidence contract

The serial UI target launches a new app process for every test and opens its
fixture through Launch Services, exercising the same user-selected read-only
sandbox extension as Finder's Open With flow. A passing execution proves these
observable outcomes:

- the empty state exposes a labeled, enabled Open video action;
- clicking the empty state and pressing Command-O each present a cancellable
  system file picker, and Cancel restores the empty state;
- H presents the labeled Shortcut Settings group and its labeled Close action
  dismisses it;
- the staged fixture reaches a ready, enabled timeline and exposes frame, zoom,
  and lock status elements;
- Space and the Play button advance frames and return to an observable paused
  state;
- step buttons, frame entry, timeline adjustment, and active-app locked
  Command-Page Down update the frame field;
- zoom entry, arrow increments, 0, and R update the zoom field;
- lock input updates the lock value and zoom-control enabled state;
- opacity entry and arrow increments update the field;
- selecting Invert disables its parameter control and shows `On`, while
  Brightness re-enables the adjustable control;
- mute/unmute updates the exposed audio state and restores the prior slider value;
- while Finder is active, each enabled registered hotkey appears exactly once,
  Command-Page Down advances exactly one frame while locked, Command-Shift-L
  unlocks, and further background stepping is rejected while unlocked.

`ZoomScreenshotTest` always asserts the 100% to 200% zoom transition.
`UITEST_SCREENSHOTS=1` only adds retained PNG evidence; omitting that variable
does not skip the behavioral assertions.

Run the target only in a logged-in, pre-authorized session:

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
- registered global shortcuts while Reframer is inactive, including
  registration-conflict reporting and exactly-once dispatch;
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
executed self-hosted UI job before signing and notarization. The live checks
above remain release evidence that must be attached to the candidate when
their behavior changes.
