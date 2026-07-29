# Reframer WebM helper source

Reframer 0.11.0 includes a separate executable named
`reframer-ffmpeg`. It is used only to decode local VP8/VP9 WebM files
into temporary QuickTime movies for playback through AVFoundation.
Networking is disabled in this helper's FFmpeg configuration.

The shipped universal helper was built from:

- FFmpeg 8.1.2:
  <https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz>
  - SHA-256:
    `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`
  - The release signature was verified against FFmpeg signing-key
    fingerprint
    `FCF986EA15E6E293A5644F10B4322F04D67658D8`.
- libvpx 1.16.0:
  <https://chromium.googlesource.com/webm/libvpx/>
  - tag object:
    `04def0a07f8bfa95785e30e6db95036cda17f9b2`
  - source commit:
    `1024874c5919305883187e2953de8fcb4c3d7fa6`
- NASM 2.16.03, used only while building the x86_64 slice:
  <https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz>
  - SHA-256:
    `1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148`

The exact build procedure and enabled FFmpeg feature surface are in
`scripts/build_media_helper.sh` in the Reframer source repository.

The checked-in pre-release-signing helper SHA-256 is:

`bb1f4d0148461b835a659a01b3898e97d375b6de57632182192bbbfe73c0154c`

Developer ID signing adds a secure timestamp and changes the complete-file
SHA-256 of the helper inside each release bundle. Release-specific checksums
therefore belong to that candidate's notarization record; the value above
proves the canonical checked-in helper before release signing.

FFmpeg is configured as LGPL 2.1-or-later code, with GPL, version-3,
and nonfree components disabled. libvpx is distributed under its
BSD-style license and patent grant. The corresponding license and
patent files are included beside this notice.

For at least three years after the last distribution of a Reframer build
containing this helper, IVG Design offers any recipient the complete
machine-readable corresponding FFmpeg/libvpx source and the Reframer source,
object/relink material, configuration, and build scripts needed to modify the
LGPL-covered library code and relink the application. Digital delivery is
available at no charge; physical transfer, if requested, will cost no more
than the actual distribution medium and postage. Request the materials through
the Reframer source repository or email
<ilyav@gusinski.us>, identifying the Reframer version and build.

This notice records the project's intended LGPL source/relink offer; it is not
legal advice. Release maintainers must retain those exact corresponding
materials for the full offer period.
