# Changelog

All notable changes to Reframer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup
- Project renamed from VideoOverlay to Reframer
- macOS deployment target set to 15.0 (Sequoia) with Tahoe (26) enhancements
- Comprehensive implementation plan in `docs/MASTER_IMPLEMENTATION_PLAN.md`
- YouTube link playback via long-press on Open button
- Preference persistence for opacity, volume, mute state, always-on-top, and window position
- Scroll step accumulator for precise trackpad stepping
- Expanded unit + UI automation coverage for scrubbing, input modifiers, filters, and persistence
- Cmd+A select-all support in numeric input fields
- On-demand libmpv installer for extended formats (WebM/MKV/VPx/AV1)
- **Homebrew Bottle Installation**: MPVManager downloads libmpv from Homebrew bottles
  - Uses ghcr.io with anonymous token authentication (no Homebrew CLI required)
  - Downloads mpv, ffmpeg, libass, and all dependencies (~30MB total)
  - Uses install_name_tool to fix @loader_path references
- **YouTube via MPV**: Route YouTube DASH streams through libmpv
  - Much faster loading (2-5 seconds vs 60+ with AVFoundation)
  - Separate audio track support for high-quality streams
  - HTTP header injection for YouTube authentication

### Fixed
- Help book documentation link now opens the correct help index
- AVFoundation load state now reflects real readiness before enabling controls
- Global shortcut permission prompt handled explicitly
- Frame/zoom/opacity inputs capture Cmd+Shift/Option/Ctrl arrow selectors
- Scroll wheel discrete stepping triggers on any tick
- Open button long-press reliably triggers YouTube prompt
- Parameterless quick filters now keep the opacity field readable while disabling edits
- Supported format detection checks UTType in addition to extensions
- Mute toggle restores last volume instead of resetting
- UI test runner now clears quarantine and re-signs before automation runs
- MPV metadata refresh now retries and uses display-size fallback for width/height

### Changed
- Filter pipeline now creates filters per frame to avoid thread-safety issues
- Global frame-step shortcuts now only fire when lock mode is enabled
- Extended format playback now uses libmpv
- **YouTube playback now requires MPV** (AVFoundation too slow - 60+ seconds)
- MPV high-precision seeking enabled for scrub accuracy
- MPVManager downloads from Homebrew bottles (stolendata.net bundles have static libmpv)

### Project Structure
- Xcode project with proper source organization (App, Views, Models, Utilities)
- App sandbox enabled with file access entitlements
- Documentation moved to `docs/` folder

## [1.0.0] - TBD

### Planned Features
- Transparent video overlay window
- Frame-accurate playback controls
- Zoom and pan with keyboard/mouse/scroll
- Adjustable opacity (2-100%)
- Lock mode (click-through)
- Drag & drop video loading
- Liquid Glass UI on macOS Tahoe
- Global keyboard shortcuts
