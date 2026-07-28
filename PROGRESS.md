# Reframer remediation progress

## 2026-07-28

- Confirmed clean current `main` at `82f9dc4`.
- Completed end-to-end audit: 6 critical, 12 high, and 6 medium findings.
- Started mission `reframer-first-class-20260728`.
- Created isolated worktrees for playback, shortcuts, and UX/accessibility.
- Integration/release track owns documentation truth, CI, metadata, security, packaging, and final validation.
- Froze the 0.10.0 product contract: macOS 15.0+, MP4/M4V/MOV, conventional Page direction, guarded global stepping, local/offline processing.
- Reconciled root/nested README, current feature/test docs, DocC, Apple Help, version metadata, and the Help search index.
- Archived stale implementation reports outside the current documentation surface and removed internal docs from the app target.
- Rebuilt CI around explicit project paths, Debug/Release builds, static analysis, unit tests, DocC, XIB checks, and bundle validation.
- Added a separate serial UI-test workflow for an interactive, normally authorized macOS runner.
- Removed runner code that edited privacy databases, restarted privacy services, removed provenance, or re-signed build products.
- Added Hardened Runtime release packaging, Developer ID verification, notarization, stapling, Gatekeeper assessment, license, and security policy.
- Verified the integration branch still builds and passes the built-bundle contract; toolbar clipping remains an intentionally enforced pending gate.
