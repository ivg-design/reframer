# Changelog

All notable changes to Reframer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0-beta.1] - 2026-02-01

### Added
- **Video filters** — Quick filter system with click-to-cycle and hold-for-menu UI
  - Brightness, Contrast, Exposure, Saturation adjustments
  - Invert filter for negative effect
  - Line Art filter for edge detection
  - Blur filter for soft overlay effect
- Filter panel for advanced multi-filter combinations
- Filter chaining support with independent parameter controls
- Edge glow indicators with soft gradient effect for resize handle discovery
- Subtle visual hints appear when hovering near window edges

### Changed
- Toolbar now positioned below video canvas instead of overlapping
- Video canvas has rounded corners on all four sides
- Pan now requires Ctrl+drag to prevent conflict with window dragging
- Improved drag-and-drop registration for video files

### Fixed
- Toolbar and canvas width mismatch (was 861px vs 800px)
- Scrubbar not resetting when loading a new video
- Scrubbar not reaching the last frame
- Window dragging accidentally causing video panning
- Timeline slider now properly updates maxValue on video load

### Supported Formats
- MP4, MOV, ProRes, H.264, H.265, AVI

## [0.7.0] - 2026-01-31

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

## [0.1.0] - 2026-01-30

### Added
- Initial commit with basic video overlay functionality
