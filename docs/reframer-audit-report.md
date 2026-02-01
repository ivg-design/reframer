# Reframer Codebase Audit Report

Date: 2026-02-01
Scope: `Reframer-filters/Reframer` (feature branch worktree), focusing on playback pipeline (AVFoundation + libmpv), filter rendering, UI state flow, install/update paths, and usage behavior.

## Summary
Reframer is generally clean and easy to follow, but there are several correctness and stability risks tied to playback state management, filter rendering, and the libmpv install/usage path. The highest-impact issues are around stale async updates (metadata and filter composition), thread-unsafe CIFilter reuse, codec detection/fallback, and incomplete MPV metadata integration. Several UX states report “loaded” before playback is verified, which makes failures hard to diagnose for users.

## Findings (ordered by severity)

### Critical / High

1) **CIFilter instances are reused across frames (thread-safety risk)**
- Evidence: `applyCurrentFilters` builds a single `filters` array and `createVideoComposition` reuses those instances inside the handler (`VideoView.swift:353-424`).
- Impact: `CIFilter` is not guaranteed thread-safe; the composition handler can run concurrently across frames, causing flicker, invalid outputs, or crashes under load.
- Fix: Create filters inside the handler (per-frame), or copy/safe-clone per request. Avoid sharing mutable CIFilter objects across threads.

2) **Async metadata and filter tasks can apply stale state to a new asset**
- Evidence: `loadVideo` starts a Task with captured `asset` and updates state after await; no cancellation or identity check (`VideoView.swift:214-255`). `applyCurrentFilters` launches a Task and applies composition after async track load without verifying current asset (`VideoView.swift:372-394`).
- Impact: Rapidly loading multiple videos can apply duration/size/filters from a previous asset, leading to wrong frame counts, render size, or composition on a different video.
- Fix: Track a load token or compare `currentAsset === asset` before mutating state. Cancel in-flight Tasks when a new video is loaded.

3) **MPV vs AVFoundation selection must account for codecs inside supported containers**
- Evidence: Selection uses a fast path (`requiresMPV` by extension) plus async codec probing (`VideoFormats.canAVFoundationPlay`).
- Impact: If codec probing regresses or is removed, unsupported codecs inside MP4/MOV could still attempt AVFoundation and fail silently.
- Fix: Keep codec probing in place and ensure fallback to MPV when AVFoundation can’t decode.

4) **AVFoundation success/failure is not observed; UI marks video as loaded before playback is verified**
- Evidence: `DropZoneView` and `AppDelegate.application(_:open:)` set `isVideoLoaded = true` immediately (`DropZoneView.swift:181-186`, `AppDelegate.swift:84-90`). `VideoView` doesn’t observe `AVPlayerItem.status` or `AVPlayerItemFailedToPlayToEndTime` (`VideoView.swift:214-268`).
- Impact: Controls and timeline become active even when the media fails to load or decode. Users get no error feedback for unsupported codecs or corrupt media.
- Fix: Set `isVideoLoaded` only after `AVPlayerItem.status == .readyToPlay`; on `.failed` show an error and reset state.

5) **MPV metadata mapping should be verified on real files**
- Evidence: `MPVVideoView.updateMediaInfo` uses mpv properties (`duration`, `container-fps`, `width`, `height`) to populate `VideoState`.
- Impact: If any property is missing or inaccurate for a codec/container, frame stepping and zoom calculations will be wrong.
- Fix: Validate `duration/fps/size` against known fixtures (WebM/VP9, AV1, MKV) and adjust property names if needed.

6) **libmpv installer assumes mpv bundle layout**
- Evidence: Installer extracts a tarball and searches for `mpv.app` and `libmpv.dylib` within it.
- Impact: If mpv bundle layout changes, install may fail silently or the library may not load.
- Fix: Validate the extracted layout, and surface actionable errors when `libmpv.dylib` isn’t found.

### Medium

7) **Fractional FPS is truncated when building video composition**
- Evidence: `frameDuration` uses `CMTimeScale(frameRate)` with a Float (`VideoView.swift:428-432`).
- Impact: 29.97/23.976 fps content gets incorrect timing, causing drift and inaccurate frame display.
- Fix: Use `CMTimeMakeWithSeconds(1.0 / Double(frameRate), preferredTimescale: 600)` or track’s `minFrameDuration`/`nominalFrameRate` with a rational timescale.

8) **MPV scrubbing accuracy depends on seek mode**
- Evidence: `MPVVideoView` issues `seek` with `absolute` or `absolute+exact`.
- Impact: If `absolute+exact` isn’t honored for a format, scrubbing may be coarse.
- Fix: Add tests that compare requested frame/time to observed output for long‑GOP formats.

9) **MPV event handling must stay off the main thread**
- Evidence: `MPVVideoView` drains events on a background queue, then dispatches UI updates to main.
- Impact: If event handling moves onto the main thread, UI stalls are likely on large files.
- Fix: Keep event drain on a background queue and limit work done on the main thread.

10) **libmpv dependency resolution relies on dynamic loader paths**
- Evidence: Loader sets `DYLD_LIBRARY_PATH` to locate bundled dependencies alongside `libmpv.dylib`.
- Impact: If the environment is locked down or paths change, libmpv may fail to load.
- Fix: Verify dependency resolution on clean machines and surface a clear install error when dlopen fails.

### Low

11) **Mute toggle resets volume to 0.5 instead of previous level**
- Evidence: `VideoState.toggleMute` always sets volume to `0.5` when unmuting (`VideoState.swift:99-102`).
- Impact: User volume preference is lost each toggle.
- Fix: Store last non-zero volume and restore it on unmute.

12) **Quick filter slider is active for filters without parameters**
- Evidence: `invert` and `noir` are “simple filters” but the slider does nothing (`VideoFilter.swift:44-98`).
- Impact: UI suggests a controllable parameter that has no effect.
- Fix: Remove slider for parameterless filters or replace with a disabled state.

13) **Move-to-Applications copies instead of moves**
- Evidence: `ensureInstalledInApplications` uses `copyItem` and does not delete the original bundle (`AppDelegate.swift:737-759`).
- Impact: User can end up with duplicate app versions and stale settings. Minor but confusing.
- Fix: Use a move or delete the original after a successful copy.

## Usage / UX Observations

- **Failure states are hard to see**: When AVFoundation fails (unsupported codec), the UI still shows a loaded state due to early `isVideoLoaded` toggles. There is no on-screen error or fallback hint.
- **MPV-only formats**: There is no indication in the open/drag UI that some formats require libmpv; users only see an install prompt when they try to open.
- **Scrubbing accuracy for MPV**: Validate FPS and size for WebM/MKV to ensure frame stepping stays accurate.

## Test / Observability Gaps

- **Unit tests focus on constants** (extensions and lists) rather than runtime playback or error handling (`ReframerTests/VideoFormatsTests.swift`).
- **No tests for AVFoundation failure paths** (unsupported codec, corrupted media, missing tracks).
- **No tests for MPV install / validation** or for WebM/MKV playback correctness.
- **Logging** is mostly `print` statements; there’s no structured logging or user-visible diagnostics for playback failure.

## Suggested Next Steps (non-code)

1) Decide the desired behavior for unsupported codecs inside supported containers (e.g., MP4 w/ VP9) and define a fallback policy (MPV or error prompt).
2) Decide how precise frame stepping and scrub positioning must be for MPV-only formats, and how to expose that in UI if precision can’t be guaranteed.
3) Define a stable libmpv installation/update path (including handling existing MPV installs).
