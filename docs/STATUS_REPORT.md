# Status Report (2026-02-01)

## What’s Done

### App behavior & fixes
- Added `KeyCodes` helper and removed magic key codes from input handling.
- Added `ScrollStepAccumulator` and wired it into `VideoView.scrollWheel` for consistent discrete trackpad steps.
- `VideoState` now supports `seekRequests` / `frameStepRequests`, tracks last requests for tests, and persists preferences (opacity/volume/mute/always-on-top/window position) with mute restore.
- `ControlBar` now issues seek/step through `VideoState`, uses fast vs accurate scrubbing, and supports Cmd/Shift/Option/Ctrl modifiers for step controls.
- `VideoView` and `VLCVideoView` subscribe to seek/frame-step requests; VLC path uses accurate seek via `VLCTime` and includes an error alert.
- `AppDelegate` updated for async open panel, window frame persistence, accessibility prompt, and lock-aware behavior.
- Global frame-step shortcuts are now gated to **lock mode** (Cmd+PageUp/Down and Shift+Cmd+PageUp/Down).
- Added Cmd+A select-all for numeric inputs (frame/zoom/opacity) across windows (field editor aware).
- Help + DocC docs updated to reflect new shortcuts and lock-only global steps.
- Help modal text updated to show global steps are lock-mode only and Cmd+A in inputs.

### Tests added/expanded
- Unit tests: `ControlBarStepTests`, `ScrollStepAccumulatorTests`, `DropZoneViewTests`, plus updates to `VideoStateTests` and `VideoFormatsTests`.
- UI tests: expanded `ReframerIntegrationTests` (scrub, input modifiers, quick filter slider disable, mute restore, Cmd+A select-all, lock-mode Cmd+PageDown stepping).
- UI tests configured for `UITEST_MODE=1` and `UITEST_SCREENSHOTS=1` gating.

### Project/config updates
- Added new source/test files to the Xcode project.
- Added a **UITest build phase** (`Unquarantine UITest Runner`) to remove quarantine/provenance/macl and re-sign the UITest runner and app before running.
- Added a **TestAction pre-action** in `Reframer.xcscheme` to remove quarantine/provenance/macl and re-sign as well.

### Docs updated
- `docs/FEATURE_TESTS.md` to track implemented tests.
- `CHANGELOG.md` (root and `Reframer/CHANGELOG.md`).
- DocC + Help Book shortcut listings.

## Blockers

### UITest runner “damaged” error
- **Symptom**: Automation launch shows `“ReframerUITests-Runner.app” is damaged and can’t be opened`.
- **Attempts so far**:
  - Pre-action in scheme to `xattr -dr` quarantine/provenance/macl and `codesign --deep --sign -` for the runner + app.
  - UITest target build phase to do the same.
  - Manual verification: `codesign --verify --deep --strict` passes; no `com.apple.quarantine` attribute present on runner.
  - `spctl --assess` still reports **rejected** for the runner (and the app) despite ad-hoc signing.
  - `com.apple.provenance` and `com.apple.macl` **persist** and appear to be the likely gating attributes.
- **Current impact**: UI automation cannot complete; `xcodebuild test` cannot run full UITests end-to-end due to Gatekeeper rejection of the runner.

## Outstanding Items

1. **Resolve UITest runner gatekeeper rejection** so automation can run without “damaged” error.
   - Need a stable fix that removes/replaces provenance/macl or signs in a way Gatekeeper accepts for local UITest runners.
   - Once resolved, re-run full `xcodebuild test` and confirm UI + unit tests pass.

2. **Re-run all tests** after runner fix to validate:
   - Unit tests
   - UI tests (including Cmd+A select-all and lock-mode global stepping)

3. **Verify global lock-mode shortcuts** in actual running app once automation works.

## Files Touched (high-level)
- App logic: `Reframer/Reframer/App/AppDelegate.swift`, `.../Views/ControlBar.swift`, `.../Views/VideoView.swift`, `.../Views/VLCVideoView.swift`, `.../Models/VideoState.swift`, `.../Utilities/KeyCodes.swift`
- Tests: `Reframer/ReframerUITests/ReframerIntegrationTests.swift`, `Reframer/ReframerTests/*`
- Project: `Reframer/Reframer.xcodeproj/project.pbxproj`, `Reframer/Reframer.xcodeproj/xcshareddata/xcschemes/Reframer.xcscheme`
- Docs: `docs/FEATURE_TESTS.md`, `Reframer/Reframer.help/.../shortcuts.html`, `Reframer/Reframer.docc/Articles/KeyboardShortcuts.md`, changelogs.
