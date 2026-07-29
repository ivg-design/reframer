# Third-party software

## Reframer WebM helper

Reframer includes `reframer-ffmpeg`, a separate, network-disabled
command-line helper used to prepare local VP8 and VP9 WebM media for
AVFoundation playback. The helper is a universal macOS executable built
for arm64 and x86_64 with a macOS 15.0 deployment target.

The shipped helper contains:

- FFmpeg 8.1.2, configured under LGPL 2.1-or-later with GPL,
  version-3, and nonfree components disabled.
- libvpx 1.16.0 under its BSD-style license and WebM patent grant.

The app bundle includes the complete FFmpeg and libvpx license texts,
the libvpx patent grant, exact source revisions, source download locations,
and the checked-in pre-release-signing helper SHA-256 in
`Contents/Resources/ThirdPartyLicenses`. Developer ID timestamped signing
changes the final nested helper's whole-file hash; candidate-specific hashes
belong with the release evidence.

Rebuild the helper with:

```bash
scripts/build_media_helper.sh
```

The script verifies pinned source versions before building both
architectures. It does not modify the checked-in helper unless passed
that destination explicitly.

Reframer communicates with the helper as a separate process through an
inherited local file descriptor. Its FFmpeg binary is compiled with networking
disabled and only file/pipe protocols enabled. The inherited sandbox profile
may include the parent app's network-client entitlement, so the claim is about
the helper's absent network implementation, not a categorical child-sandbox
denial. It is re-signed as nested code for every Developer ID package.

Because the helper statically links LGPL-covered FFmpeg code, the bundled
`SOURCE.md` contains the written source/relink-material offer: at least three
years from the last distribution, complete machine-readable corresponding
source plus application object/relink material and build scripts, digital
delivery at no charge, and physical delivery at no more than actual medium and
postage cost. Release maintainers must retain the exact materials for that
period. This project record is not legal advice.
