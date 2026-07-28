# Reframer threat model

This model covers Reframer 0.10.0's local-video, overlay, and shortcut
boundaries. Revisit it before adding networking, an updater, plug-ins,
scripting, third-party codecs, or persistent access to media.

## Assets and trust boundaries

- User videos remain outside Reframer's container. App Sandbox grants
  read-only access only after the user selects, drops, or opens a video with
  Reframer.
- A security-scoped URL is retained only while that video is active. Reframer
  does not persist a bookmark or reopen the video after relaunch.
- Preferences live in Reframer's sandbox container and contain settings, not
  video contents.
- AVFoundation and Core Image are the only playback and image-processing
  frameworks. No downloaded or third-party executable code is loaded.

## Keyboard input

Reframer uses Carbon's registered-hot-key API. During normal operation, the
enabled global lock chord stays registered in every video and lock state. The
four frame-step variants are registered only while a video is loaded, the
overlay is locked, and exact or estimated sample navigation is available. They
are removed outside that state, so Reframer cannot receive or swallow those
keys when frame navigation is not actionable.

Registration describes exact virtual key and modifier combinations; it does
not expose unrelated keystrokes. Registrations are exclusive so an existing
owner produces a detectable failure instead of ambiguous multi-app dispatch.
Reframer shows that failure and a retry action.

The app does not use a global `NSEvent` monitor, event tap, Accessibility API,
or Input Monitoring permission. Local key handling runs only while Reframer is
active. Text editors keep text and standard edit commands, while other focused
controls keep only conventional activation and navigation keys.

## Abuse resistance

- Global frame-step chords are not registered unless a video is loaded, the
  overlay is locked, and exact or estimated navigation is available.
- Nonrepeating actions suppress repeated press events; step actions retain
  key-repeat behavior.
- Binding validation rejects duplicates, macOS-reserved chords, multiplier
  collapse, unsupported keys, and globals without Command or Control.
- Registration is rebuilt after binding, global-enable, video, lock, or
  navigation-availability changes. All registrations are suspended during
  shortcut recording and removed on shutdown.

## Release controls

A release must be universal, Hardened Runtime enabled, App Sandbox enabled,
signed with Developer ID, notarized, stapled, and Gatekeeper assessed. The
only allowed entitlements are `com.apple.security.app-sandbox` and
`com.apple.security.files.user-selected.read-only`. Repository and release
validators reject broad global event monitors, privacy-database mutation, and
unexpected entitlements. The remediation run did not have Apple distribution
credentials, so Developer ID signing, notarization, stapling, and Gatekeeper
acceptance remain external release evidence rather than completed local
checks.
