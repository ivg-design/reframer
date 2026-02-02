# Changelog

All notable changes to Reframer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2025-02-01

### Added
- Real-time video filters (Grayscale, Sepia, Invert, Noir, etc.)
- Quick filter dropdown in toolbar with adjustable intensity
- Advanced filter panel for stacking multiple effects
- Edge glow indicators with soft gradient effect for resize handle discovery
- Subtle visual hints appear when hovering near window edges (when unlocked)
- 100ms debounce to prevent flickering on edge hover
- Preference persistence for opacity, volume, mute state, always-on-top, and window position
- Scroll step accumulator for precise trackpad stepping
- Expanded unit test coverage for filters and persistence
- Cmd+A select-all support in numeric input fields

### Changed
- Toolbar now positioned below video canvas instead of overlapping
- Video canvas has rounded corners on all four sides
- Pan now requires Ctrl+drag to prevent conflict with window dragging
- Improved drag-and-drop registration for video files
- Timeline scrubbing uses fast seeks while dragging and accurate seeks on release
- Open panel is asynchronous (non-blocking)
- Default appearance forced to Dark mode
- Control bar height increased to 80pt to avoid clipping
- Quick filter slider disables for parameterless filters (Invert/Noir)
- Global frame-step shortcuts now only fire when lock mode is enabled

### Fixed
- Global shortcut permission prompt handled explicitly
- Frame/zoom/opacity inputs capture Cmd+Shift/Option/Ctrl arrow selectors
- Scroll wheel discrete stepping triggers on any tick
- Parameterless quick filters now keep the opacity field readable while disabling edits
- Supported format detection checks UTType in addition to extensions
- Mute toggle restores last volume instead of resetting
- Toolbar and canvas width mismatch (was 861px vs 800px)
- Scrubbar not resetting when loading a new video
- Scrubbar not reaching the last frame
- Window dragging accidentally causing video panning
- Timeline slider now properly updates maxValue on video load

## [1.0.0] - 2025-01-31

### Added
- Pure AppKit implementation (migrated from SwiftUI)
- Transparent frameless window with video overlay
- Always-on-top window mode
- Frame-accurate video navigation (step forward/backward)
- Zoom and pan controls with keyboard and mouse support
- Adjustable opacity (2-100%)
- Lock mode to click through video
- Comprehensive keyboard shortcuts
- Drag-and-drop video loading
- Apple Help Book documentation
- DocC API documentation
- CI workflow for automated builds

### Supported Formats
- MP4, MOV, ProRes, H.264, H.265, AVI

## [0.1.0] - 2025-01-30

### Added
- Initial commit with basic video overlay functionality
