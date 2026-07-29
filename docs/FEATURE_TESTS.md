# Reframer feature verification

Feature claims use four distinct evidence classes. A source build is not runtime
evidence, a unit test is not an AppKit interaction, and an XCUITest that only
finds an element is not proof of the action behind it.

## Automated quality gates

| Gate | What a passing result proves | What it does not prove |
|---|---|---|
| `scripts/validate_repository.sh` | Metadata, public-doc, project, scheme, XIB, resource, workflow, and synchronous lock-policy source invariants match the repository contract | Runtime behavior |
| Debug and Release builds | All production sources and resources compile and link in both configurations | A user can complete a workflow |
| `xcodebuild analyze` | Xcode static analysis reports no blocking issue | Absence of every runtime defect |
| `TEST_SCOPE=unit scripts/runner_test.sh` | Deterministic model and AppKit contract tests pass | WindowServer event routing, visual output, or another-app shortcuts |
| `xcodebuild docbuild` | DocC compiles; bundle validation separately checks Apple Help packaging | Documentation accuracy beyond the validated contract |
| `scripts/validate_bundle.sh` | The universal bundle matches the version, per-slice deployment target, exact Contents/signature/executable/runtime/Help allowlists, modern Help index, source stamp, source privacy allowlist, and contains no symlinks; an optional top-level stapled ticket must validate with `stapler` | Embedded release entitlements, Developer ID trust, notarization, or Gatekeeper acceptance when no ticket is present |
| Release packaging workflow | The extracted final ZIP passed bundle, signing, notarization-ticket, and Gatekeeper verification after the source app passed the same post-staple gates | Behavior not exercised by the preceding test jobs |

`build-for-testing` is a compile gate for both test targets. It is not recorded
as a UI-test pass unless `xcodebuild test` executes the tests and produces a
successful result bundle. On every exit, the runner unregisters temporary
Reframer apps and deletes only its sentinel-owned DerivedData; text logs and UI
result bundles remain as diagnostics without retained `.app` products.

## Deterministic unit evidence

The unit target currently proves:

- MP4, M4V, and MOV are the only advertised extensions and content types, and
  preflight accepts a known playable fixture while rejecting a missing file,
  corrupt data with a supported extension, and a valid audio-only MP4.
  Synthetic MOV and M4V container fixtures also reach the ready,
  exact-navigation playback state.
- Frame lookup uses presentation timestamps. Packaged media exercises exact
  23.976, 29.97, 59.94, and 60.00 fps sample indexing plus a real
  variable-frame-rate fixture with irregular intervals. An in-memory table
  covers additional variable timing, while the estimated-timeline tests cover
  fractional-rate fallback.
- Multi-track selection rejects unusable tracks and prepares one coherent,
  enabled video source for playback, Core Image filtering, metadata, and
  indexing while retaining usable audio only across the selected video's
  presentation range. Non-right-angle transformed frame bounds are covered.
  Exact mapping is bounded at 2,000,000 samples and deterministically falls
  back to the labeled estimate.
- First/last clamping, repeated generations, 1/10-frame direction, rapid burst
  accumulation, preview cancellation, structured indexing cancellation, load
  replacement-pauses-playback, and unload-during-load are deterministic checks.
- Playback intent is main-thread-owned and revisioned. Reconciliation proves a
  delayed AVPlayer playing status cannot revive a rapid pause. A
  generation-scoped two-second startup gate protects only transient paused
  reports, settles on playing, and clears intent if AVPlayer has settled paused
  after expiry with no authorized seek or scrub handoff pending. Real AVPlayer
  lifecycle tests prove startup advances, EOF replay and scrub resume accept
  only the current intent revision, a newer Pause rejects those deferred
  completions, a newer Play reauthorizes the existing seek, and physical
  transport remains paused throughout scrub/seek handoff. Scrub end performs a
  synchronous handoff without an unprotected pause window.
- Delayed exact-index installation remaps the latest estimated presentation
  time onto the exact VFR table, preserves replay intent, assigns a new
  generation, rejects the stale completion, and keeps a deferred filter refresh
  pending until it is safe.
- Per-load security-scoped leases have deterministic balance and ordering
  checks: failed acquisition never stops, successful acquisition stops once
  after the final reference, replacement starts before old release, cancelling
  work retains access until it unwinds, and player teardown precedes release.
- Playback, scrub, zoom, opacity, mute, filter, and persistence state
  transitions obey their model contracts.
- Shortcut defaults, local/global scope, 1/10/100 multipliers, repeat policy,
  collision/reserved-key rejection, migration, clear/disable/re-enable, and
  persistence resolve to typed commands. The exact Carbon registration plan,
  lock-only versus actionable-frame registration lifecycle, AppKit-to-Carbon
  modifier mapping, conflict/retry state, focused-control ownership,
  non-repeat event consumption, incremental registration retention across a
  held lock chord, exact registered-recovery prerequisite for lock entry,
  forced unlock after recovery loss, system-sheet bypass, native
  table/document navigation, and active-versus-inactive dispatch policy also
  have unit coverage.
- Window recovery, one-time migration from the former split-window footprint,
  whole-overlay placement, attached-panel placement, and invalid geometry
  handling are checked as pure geometry.
- The locked-window policy matrix proves that lock forces the public status-bar
  level above all ordinary application windows, including normal, floating,
  modal, and utility windows; pointer transparency; and
  nonmovable/nonresizable geometry regardless of the saved Always on Top When
  Unlocked preference, while unlock restores that preference. It does not
  claim precedence over higher critical system UI.
- AppKit hierarchy coverage proves that video and controls share one canonical
  window with no separately managed control child.
- Responsive control-bar coverage fixes the preferred width at 1,060 points,
  the supported minimum at 640, and the layout breakpoint at 920. It checks the
  48-point one-row and 96-point two-row modes, exact row membership, worst-case
  visible controls and long metadata, absence of overlap, and the reported
  preferred-height transition without replacing the accessible controls.
- Drop-zone actionability, quick-filter menu contents, advanced-filter control
  naming/focus, lock-aware drag-handle state, status text, independently
  reachable ready-state badges, complete slider role/range/orientation, and
  pointer-transparent overlays are checked through AppKit objects.
- The native documentation loader rejects traversal outside the bundled Help
  root, renders known nonblank Help text in an AppKit text view, and provides
  an explicit fallback page for missing content without requiring WebKit or
  network access.

These checks do not prove that macOS delivered a physical key, pointer, drag,
display, accessibility, or workspace event to the running app.

## XCUITest evidence contract

The serial UI target launches a new app process with an isolated preference
suite for every test. It opens its fixture through Launch Services, exercising
the same user-selected read-only sandbox-extension path as Finder's Open With
flow.

The bullets below define what a passing execution proves. Candidate-specific
results belong in the dated
[audit and release-readiness record](AUDIT_2026-07-28.md), not in this stable
test contract:

- the empty state exposes a labeled, enabled Open video action;
- clicking the empty state and pressing Command-O each present a cancellable
  system file picker, and Cancel restores the empty state;
- with a video loaded, native Down/Space input in the replacement file picker
  does not pan, step, or toggle playback;
- H presents the labeled Shortcut Settings group and its labeled Close action
  dismisses it;
- video and controls are descendants of the named primary overlay window, and
  no separately targetable controls window is exposed;
- the Launch Services fixture reaches a ready, enabled timeline and exposes
  frame, zoom, and lock status elements;
- Space and the Play button each reach `Playing`, advance frames, remain stably
  `Playing`, and then return to an observable `Paused` state;
- step buttons, frame entry, and timeline adjustment update the frame field;
- while Reframer is active, Command-Page Down, Command-Shift-Page Down,
  Command-Page Up, and Command-Shift-Page Up exercise both directions and the
  one/ten-sample factors;
- zoom entry, arrow increments, 0, and R update the zoom field;
- lock input updates the lock value and zoom-control enabled state; locked
  controls become disabled and local keyboard unlock restores their
  actionability;
- opacity entry and arrow increments update the field;
- selecting Invert disables its parameter control and shows `On`, while
  Brightness re-enables the adjustable control;
- mute/unmute updates the exposed audio state and restores the prior slider
  value;
- F and Command-? open their named panels, documentation exposes known
  nonblank bundled Help text in a native selectable text view, keeps native
  Space input without toggling playback, and Escape closes each panel;
- Space activates a focused Quick Filter button or filter switch without also
  toggling playback;
- rebinding Play/Pause from Space to J removes the old chord, activates the new
  chord, survives relaunch, can be disabled, and remains disabled after another
  relaunch;
- the actionable state reports five system-accepted registrations (lock plus
  four frame variants), the inactive app retains those registrations, the
  unlocked state reports only the lock registration, and relocking restores
  all five.

XCUITest `typeKey` events are targeted directly at the named application and
do not traverse WindowServer's Carbon hot-key route. The UI target therefore
does not claim physical cross-application delivery from those synthetic
events; that remains an explicit live gate below.

`ZoomScreenshotTest` always asserts the 100% to 200% zoom transition.
`UITEST_SCREENSHOTS=1` only adds retained PNG evidence; omitting that variable
does not skip the behavioral assertions.

Warning: XCUITest launches and foregrounds Reframer and takes keyboard focus.
It is not a background test merely because `xcodebuild` starts from Terminal.
Every run requires fresh operator authorization. Without that authorization,
use only the background-safe unit command:

```bash
TEST_SCOPE=unit scripts/runner_test.sh
```

With fresh authorization, run the UI target only in an unlocked, logged-in
session:

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
- unlocked macOS and Mosaic move/resize operations targeting the one canonical
  window—including the configured Command-Shift-Left/Right/Up/Down screen-half
  shortcuts and minimum-size behavior—with the video and control bar remaining
  integral;
- one 48-point control row at 920 points and wider, two rows totaling 96 points
  below 920 through the 640-point minimum, and every control remaining visible,
  keyboard-focusable, and accessibility-reachable in both modes;
- Always on Top When Unlocked restoration after unlock;
- refusal to enter lock when the exact configured global Lock/Unlock chord is
  not registered, plus automatic unlock and visible recovery guidance if
  registration later disappears, conflicts, is suspended during recording, or
  global shortcuts are disabled;
- locked public status-bar level above all foreground ordinary application
  windows, including normal, floating, modal, and utility windows;
  whole-overlay click-through including the control bar; rejection of
  move/resize attempts; and recovery with the global lock shortcut from the app
  underneath;
- confirmation that system pop-up menus, drag UI, the screen saver, and
  assistive-technology UI retain their higher critical-system precedence;
- registered lock and all four frame-step chords physically dispatching once
  from another app, plus unlocked frame chords reaching an observable receiver
  there to prove the unregistered chord was not swallowed;
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
executed self-hosted UI job before signing and notarization. The live checks
above remain candidate evidence and must be attached whenever their behavior
changes. A local unsigned pass never substitutes for Developer ID signing,
notarization, stapling, or Gatekeeper assessment.
