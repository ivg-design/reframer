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

### Fixed
- Help book documentation link now opens the correct help index
- AVFoundation load state now reflects real readiness before enabling controls
- VLCKit plugin install now mounts DMG robustly and validates plugins recursively

### Changed
- Filter pipeline now creates filters per frame to avoid thread-safety issues

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
