# Handoff Report (Session 4) — Remote Test Runner

This handoff is retained for the remote test runner setup and workflow. Legacy playback notes were removed in favor of the current libmpv implementation.

## Remote Test Runner Summary

- **Runner host**: `laptop` (SSH alias to `ivg@192.168.2.107`)
- **Repo path on runner**: `/Users/ivg/github/video-overlay/Reframer-filters/Reframer`
- **Goal**: Build and run AppKit UI tests without focus‑stealing on the main Mac

### Typical Workflow

```bash
# Sync repo
rsync -av --delete /Users/ivg/github/video-overlay/Reframer-filters/Reframer/ laptop:/Users/ivg/github/video-overlay/Reframer-filters/Reframer/

# Build
ssh laptop "cd /Users/ivg/github/video-overlay/Reframer-filters/Reframer && xcodebuild -scheme Reframer -configuration Debug -destination 'platform=macOS' build"

# Run app with test mode
ssh laptop "export UITEST_MODE=1 && /Users/ivg/Library/Developer/Xcode/DerivedData/Reframer-*/Build/Products/Debug/Reframer.app/Contents/MacOS/Reframer"

# Run UI tests
ssh laptop "cd /Users/ivg/github/video-overlay/Reframer-filters/Reframer && xcodebuild -scheme Reframer -destination 'platform=macOS' test"
```

### Notes
- Keep the runner user logged in to allow AppKit UI tests to interact with windows.
- Accessibility permissions must be granted once on the runner.

---

*Last Updated: 2026-02-01 12:30*
