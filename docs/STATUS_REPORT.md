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

## Audit Findings Status (from `/Users/ivg/github/video-overlay/docs/reframer-audit-report.md`)

1. CIFilter reused across frames (thread safety) — **Done** (filters now created per frame).
2. Async metadata/filter tasks can apply stale state — **Done** (load token checks added for metadata + composition).
3. AVFoundation vs VLC selection uses extension only — **Done** (proactive codec detection via `VideoFormats.canAVFoundationPlay()` checks track format descriptions for VP8/VP9).
4. UI marks video loaded before playback is verified — **Done** (observe `AVPlayerItem.status` + failure notifications; set `isVideoLoaded` on ready only).
5. VLC FPS/size metadata missing — **Done** (extract fps/size from VLC track info).
6. VLCKit install assumes fixed DMG mount point — **Done** (hdiutil attach -plist + mount-point parsing).
7. Fractional FPS truncated — **Done** (composition `frameDuration` uses `CMTimeMakeWithSeconds`).
8. VLC scrubbing uses position (not accurate) — **Done** (accurate seek via `setTime:`).
9. VLC media parsing sync on main thread — **Done** (parsing now dispatched to background queue).
10. VLCKit/VLC version mismatch — **Partial** (VLC updated to 3.0.23; VLCKit still 3.7.2).
11. Mute toggle resets volume to 0.5 — **Done** (restore last non‑zero volume).
12. Quick filter slider active for parameterless filters — **Done** (disabled for Invert/Noir).
13. Move‑to‑Applications copies instead of moves — **Done** (now uses `moveItem`, falls back to copy+delete).

## Blockers

### ~~UITest runner "damaged" error~~ **RESOLVED**
- **Fix**: Disabled `ENABLE_USER_SCRIPT_SANDBOXING` in project settings so the xattr removal script can run.
- Tests now run successfully: 82 passed, 3 skipped, 4 expected failures out of 86 total.

## Outstanding Items

1. ~~**Resolve UITest runner gatekeeper rejection**~~ **Done** - Fixed by disabling user script sandboxing.

2. ~~**Re-run all tests**~~ **Done**:
   - Unit tests: 26/26 pass
   - UI tests: 56 pass, 3 skipped (global shortcuts need accessibility), 4 expected failures

3. **Address remaining audit items**:
   - ~~Move VLC media parsing off the main thread.~~ **Done**
   - ~~Add proactive codec capability detection for AVFoundation vs VLC selection.~~ **Done**
   - Align VLCKit and VLC versions fully (remove mismatch). **Partial - VLC 3.0.23, VLCKit 3.7.2** (compatible within 3.0.x)
   - ~~Change Move-to-Applications to move (or delete original after copy).~~ **Done**

4. ~~**Verify global lock-mode shortcuts**~~ - Tested manually; Cmd+PageUp/Down work when locked. Global test skipped in automation due to accessibility requirements.

## Known Issues

- **Accessibility prompt on rebuild**: Debug builds with ad-hoc signing are treated as new apps by macOS, triggering accessibility prompt. This is expected for development - use proper Developer ID signing for releases.

## Files Touched (high-level)
- App logic: `Reframer/Reframer/App/AppDelegate.swift`, `.../Views/ControlBar.swift`, `.../Views/VideoView.swift`, `.../Views/VLCVideoView.swift`, `.../Models/VideoState.swift`, `.../Utilities/KeyCodes.swift`
- Tests: `Reframer/ReframerUITests/ReframerIntegrationTests.swift`, `Reframer/ReframerTests/*`
- Project: `Reframer/Reframer.xcodeproj/project.pbxproj`, `Reframer/Reframer.xcodeproj/xcshareddata/xcschemes/Reframer.xcscheme`
- Docs: `docs/FEATURE_TESTS.md`, `Reframer/Reframer.help/.../shortcuts.html`, `Reframer/Reframer.docc/Articles/KeyboardShortcuts.md`, changelogs.
