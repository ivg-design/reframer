# Reframer Codebase Audit Report

Date: 2026-02-01
Scope: `Reframer-filters/Reframer` (feature branch worktree), focusing on playback pipeline (AVFoundation + VLCKit), filter rendering, UI state flow, install/update paths, and usage behavior.

## Summary
Reframer is generally clean and easy to follow, but there are several correctness and stability risks tied to playback state management, filter rendering, and the VLCKit install/usage path. The highest-impact issues are around stale async updates (metadata and filter composition), thread-unsafe CIFilter reuse, codec detection/fallback, and incomplete VLC metadata integration. Several UX states report “loaded” before playback is verified, which makes failures hard to diagnose for users.

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

3) **VLC vs AVFoundation selection only uses file extension**
- Evidence: `MainViewController.handleVideoURLChange` uses `vlcOnlyExtensions` only (`MainViewController.swift:122-139`). `VideoFormats.isSupported` also uses extension only (`VideoFormats.swift:62-74`).
- Impact: Files with unsupported codecs inside “supported” containers (e.g., VP9/AV1 in MP4) will still go through AVFoundation and fail silently. Users see a blank player with controls enabled.
- Fix: Detect codec support via `AVURLAsset`/`AVAssetTrack` (`isPlayable`, format descriptions) and fall back to VLC if AVFoundation can’t decode.

4) **AVFoundation success/failure is not observed; UI marks video as loaded before playback is verified**
- Evidence: `DropZoneView` and `AppDelegate.application(_:open:)` set `isVideoLoaded = true` immediately (`DropZoneView.swift:181-186`, `AppDelegate.swift:84-90`). `VideoView` doesn’t observe `AVPlayerItem.status` or `AVPlayerItemFailedToPlayToEndTime` (`VideoView.swift:214-268`).
- Impact: Controls and timeline become active even when the media fails to load or decode. Users get no error feedback for unsupported codecs or corrupt media.
- Fix: Set `isVideoLoaded` only after `AVPlayerItem.status == .readyToPlay`; on `.failed` show an error and reset state.

5) **VLC playback does not derive actual FPS/size and uses defaults**
- Evidence: `VLCVideoView.updateMediaInfo` sets duration but not fps; uses `state.frameRate` (default 30) to compute total frames and uses a hard-coded 1920x1080 size (`VLCVideoView.swift:358-377`).
- Impact: Frame stepping, timeline, zoom/fit, and frame count are wrong for VLC-only formats. This undermines scrubbing accuracy and UI correctness.
- Fix: Query VLC’s video track info (e.g., `media.tracksInformation` or `VLCMediaTracksInformation`) for real FPS/size, and update `VideoState` accordingly.

6) **VLCKit install depends on a fixed DMG mount point**
- Evidence: `extractPluginsFromDMG` assumes `/Volumes/VLC media player` (`VLCKitManager.swift:293-316`).
- Impact: Installation can fail if the volume name differs, is localized, or already mounted (mount point may become `VLC media player 1`). Failures are hard to diagnose.
- Fix: Use `hdiutil attach -plist` and parse the actual mount point, or pass a custom mount directory.

### Medium

7) **Fractional FPS is truncated when building video composition**
- Evidence: `frameDuration` uses `CMTimeScale(frameRate)` with a Float (`VideoView.swift:428-432`).
- Impact: 29.97/23.976 fps content gets incorrect timing, causing drift and inaccurate frame display.
- Fix: Use `CMTimeMakeWithSeconds(1.0 / Double(frameRate), preferredTimescale: 600)` or track’s `minFrameDuration`/`nominalFrameRate` with a rational timescale.

8) **VLC scrubbing uses position-based seeking, not frame-accurate**
- Evidence: `seek(to:)` calls `setPosition:` with a 0..1 float (`VLCVideoView.swift:259-263`).
- Impact: Scrubbing jumps to keyframes or coarse positions, especially on long GOP encodes.
- Fix: Use `setTime:` with milliseconds, and update frame stepping with actual frame duration.

9) **VLC media parsing occurs synchronously on the main thread**
- Evidence: `media.perform(parse)` happens during `loadVideo` on the main thread (`VLCVideoView.swift:213-217`).
- Impact: UI stalls on large or remote files, potentially causing “stuck” perception.
- Fix: Use async parse APIs or dispatch parsing to a background queue, then update UI.

10) **VLCKit and VLC plugins are version-mismatched**
- Evidence: VLCKit tarball 3.7.2 with VLC.app 3.0.21 plugins (`VLCKitManager.swift:11-18`).
- Impact: ABI or plugin compatibility issues can cause playback failure or unstable behavior with certain codecs.
- Fix: Align VLCKit and VLC versions (same major/minor), or bundle a known-good VLC build that matches VLCKit.

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
- **VLC-only formats**: There is no indication in the open/drag UI that some formats require VLCKit; users only see an install prompt when they try to open.
- **Scrubbing accuracy for VLC**: Without real FPS and size, frame stepping and timeline values for WebM/MKV are not reliable.

## Test / Observability Gaps

- **Unit tests focus on constants** (extensions and lists) rather than runtime playback or error handling (`ReframerTests/VideoFormatsTests.swift`).
- **No tests for AVFoundation failure paths** (unsupported codec, corrupted media, missing tracks).
- **No tests for VLC install / plugin validation** or for WebM/MKV playback correctness.
- **Logging** is mostly `print` statements; there’s no structured logging or user-visible diagnostics for playback failure.

## Suggested Next Steps (non-code)

1) Decide the desired behavior for unsupported codecs inside supported containers (e.g., MP4 w/ VP9) and define a fallback policy (VLC or error prompt).
2) Decide how precise frame stepping and scrub positioning must be for VLC-only formats, and how to expose that in UI if precision can’t be guaranteed.
3) Align VLCKit/VLC versions and define a stable installation/update path (including handling existing VLC installs).

