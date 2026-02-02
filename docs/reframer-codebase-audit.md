# Reframer Codebase Audit (2026-02-02)

Scope: `/Users/ivg/github/video-overlay/Reframer-filters` on branch `feature/video-filters`.

## Recent changes observed
- Recent commits on the branch include work on UI test runners, help/filters UX, and YouTube prompt handling (see `git log` entries around `c2243bf`, `ed20da0`, `128b97b`, `f8ab548`).
- Current working tree has uncommitted modifications in:
  - `Reframer/Reframer/App/AppDelegate.swift`
  - `Reframer/Reframer/Utilities/KeyCodes.swift`
  - `Reframer/Reframer/Utilities/MPVManager.swift`
  - `Reframer/Reframer/Views/VideoView.swift`

## Findings (ordered by severity)

### High
- MPV installation is fragile and may produce partial, unusable installs. `MPVManager.install` downloads multiple Homebrew bottles but ignores per-package failures and still reports success. Missing dependencies will surface later as runtime dlopen errors. (`Reframer/Reframer/Utilities/MPVManager.swift`)
- Dependency path rewriting is incomplete. `fixLibraryPaths` only rewrites `@@HOMEBREW_PREFIX@@` references. Bottles that embed absolute `/opt/homebrew/...` paths will still fail at runtime unless those paths exist on the host. `DYLD_LIBRARY_PATH` does not fix absolute install names. (`Reframer/Reframer/Utilities/MPVManager.swift`)

### Medium
- `VideoFormats.canAVFoundationPlay` hard-fails on VP8/VP9/AV1 even on systems that may support AV1 natively. This can cause unnecessary MPV routing and downgrade quality. It also only inspects video track subtypes and does not account for audio codec incompatibility or other AVFoundation limitations. (`Reframer/Reframer/Utilities/VideoFormats.swift`)
- The MPV install pipeline uses multiple `Process` calls (`tar`, `otool`, `install_name_tool`) without timeouts or explicit error handling in all cases. A hung process will hang installation. Copying all `.a` static archives is unnecessary and increases install size. (`Reframer/Reframer/Utilities/MPVManager.swift`)
- `DYLD_LIBRARY_PATH` is set globally for the app and never restored. This can alter dynamic loading behavior for unrelated components and complicate debugging. (`Reframer/Reframer/Utilities/MPVManager.swift`)
- Enter/Escape in text fields forces `NSApp.hide/unhide` to return focus to the previous app. This is a brittle UX hack that can flicker the UI, trigger Mission Control, or interfere with accessibility tooling. (`Reframer/Reframer/App/AppDelegate.swift`)

### Low
- `toggleMinimize` assumes `mainWindow` is initialized; if triggered before window creation it could crash. The control window has no `.miniaturizable` style mask and depends on child-window behavior for minimization. (`Reframer/Reframer/App/AppDelegate.swift`)
- `VideoView.stepFrame` updates `currentTime`/`currentFrame` before `seekToFrame` completes. If seek fails or is throttled, UI state may briefly diverge from rendered content. (`Reframer/Reframer/Views/VideoView.swift`)

## Test and verification gaps
- MPV install/update is not covered by automated tests; failures will only show up at runtime when a user opens a non-AVFoundation format.
- YouTube playback tests rely on env vars and external network tools (`yt-dlp`), but there is no deterministic integration test for native playback vs MPV routing.
- There is no automated test for window minimization or for the new Cmd+A select-all behavior in text fields.

## Recommended next steps
- Make MPV installation transactional: track failures, require `mpv` and its critical dependencies, and fail installation if any required bottle fails.
- Expand library path rewriting to handle absolute Homebrew paths (or avoid rewriting by using `@rpath`/`@loader_path` during install). Add verification that `dlopen` of `libmpv` succeeds before reporting success.
- Ensure YouTube routing remains MPV-only (by design for performance) and make MPV install/enablement UX resilient since YouTube playback depends on it.
- Update `VideoFormats.canAVFoundationPlay` to allow AV1 on supported systems and to validate both video and audio tracks using `CMFormatDescription` plus `AVAsset` `isPlayable` checks.
- Add explicit timeouts for external processes and use structured error reporting. Avoid copying `.a` files into the runtime lib directory.
