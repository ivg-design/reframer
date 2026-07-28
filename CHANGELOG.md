# Changelog

Notable Reframer changes are recorded here. The project uses semantic
versioning once a build is published; earlier repository milestones were
development snapshots, not production releases.

## [0.10.0] - Unreleased

### Added

- Canonical command registry and single dispatcher for key, menu, and global
  input
- Shortcut validation, clear/disable/reset behavior, persistence migration,
  registered-hot-key conflict status, and deterministic command tests
- Desired-sample playback cursor, generation-scoped async work, exact final
  scrub seeks, load/error/end-state handling, and media preflight
- Keyboard and VoiceOver semantics for the empty state, toolbar, filters,
  panels, overlays, and status
- Reduce Motion and multi-display-safe presentation behavior
- Machine-readable product contract and repository/bundle validators
- Separate CI and interactive macOS UI-test workflows
- Developer ID archive, universal-binary verification, notarization, stapling,
  and Gatekeeper packaging
- MIT license and security/threat-model documentation

### Changed

- Minimum system and public documentation are aligned at macOS 15.0
- Shipping containers are explicitly MP4, M4V, and MOV through AVFoundation
- Page Down advances and Page Up reverses
- Global frame stepping requires a loaded video and lock mode
- Frame navigation uses decoded sample timing instead of rounded nominal-rate
  arithmetic
- Quick filters use a conventional primary-click menu with a separate advanced
  panel
- App resources are explicitly allowlisted; engineering reports remain outside
  the app bundle
- Version and build metadata now derive from Xcode build settings and include a
  source stamp

### Fixed

- Decorative edge and status overlays no longer block pointer input
- Opacity and other advertised preferences persist after relaunch
- Toolbar controls no longer clip at the minimum window size
- Rebinding a command removes its previous chord and prevents duplicate
  dispatch
- Focused buttons and generic controls no longer swallow plain or Shift-based
  Reframer shortcuts they do not own
- Stale load, seek, scrub, and filter completions cannot overwrite newer state
- Ended playback can replay from the beginning
- UI tests run serially and no longer mutate macOS privacy or signing state

### Security

- Removed the obsolete library-validation exception
- Replaced broad global keyboard monitoring with exact, exclusive registered
  hot keys that require no Accessibility or Input Monitoring permission
- Enabled App Sandbox with user-selected, read-only video access
- Removed scripts that wrote to privacy databases, restarted privacy services,
  stripped provenance, or re-signed test products
- Documented keyboard and file-access trust boundaries and release gates

## Development snapshots

The prior 0.1 and 0.8 repository snapshots established the AppKit overlay,
playback controls, zoom/pan, filters, persistence, help content, and initial
tests. Their feature reports are preserved under
`docs/archive/legacy-implementation/` and do not define current behavior.
