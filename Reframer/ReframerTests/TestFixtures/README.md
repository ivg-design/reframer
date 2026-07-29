# Reframer test-video fixtures

Every media file in this directory is synthetic. The video fixtures use
FFmpeg `lavfi` test patterns, and the audio-only fixture uses a generated sine
wave. They contain no third-party footage, recorded voices, or user media.

The checked-in files were generated or verified with FFmpeg 7.1.1
(`Lavf61.7.100`, `Lavc61.19.101`), its MJPEG, DV, MPEG-1, and MPEG-2 encoders,
libx264, and libvpx. Tests assert media semantics such as container acceptance,
frame count, presentation timestamps, alpha metadata, audio mapping, and aspect
ratio. Encoder and muxer versions can change encoded bytes, so SHA hashes are
not generally expected to remain stable across tool versions.

## Fixture inventory

| File | Synthetic media contract | Test purpose |
| --- | --- | --- |
| `test-video.mp4` | 160×90 H.264 test pattern, 1,291 frames at 30000/1001 fps | Long fractional-rate exact indexing and load cancellation |
| `test_30fps_2s.mp4` | 1920×1080 H.264 test pattern, 60 frames at 30 fps | Standard MP4 preflight, metadata, and playback |
| `test_60fps_5s.mp4` | 1920×1080 H.264 test pattern, 300 frames at 60 fps | High-frame-rate exact indexing |
| `test_4x3_1s.mp4` | 640×480 H.264 test pattern, 30 frames at 30 fps | Aspect-ratio and replacement-load behavior |
| `test_23976fps_24f.mp4` | 64×64 H.264 test pattern, 24 frames at 24000/1001 fps | 23.976 fps presentation timestamps |
| `test_5994fps_60f.mp4` | 64×64 H.264 test pattern, 60 frames at 60000/1001 fps | 59.94 fps presentation timestamps |
| `test_vfr_11f.mp4` | 64×64 H.264 test pattern with 11 usable frames: six frames on a 100 ms cadence followed by five on a 50 ms cadence | Variable-frame-rate indexing and nearest-frame lookup |
| `test_audio_only.mp4` | 200 ms mono AAC 440 Hz sine wave; no video track | Rejection of a valid supported container without video |
| `test_playable.mov` | 64×64 H.264 test pattern, six frames at 30 fps | Real MOV-container preflight |
| `test_playable.m4v` | 64×64 H.264 test pattern, six frames at 30 fps in an MP4-family container | Real M4V-extension preflight |
| `test_playable.avi` | 64×64 MJPEG test pattern, four frames at 6 fps | Real AVI preflight and playback-composition preparation |
| `test_playable.dv` | 720×480 NTSC DV test pattern, two frames at 30000/1001 fps | Real raw-DV preflight and playback-composition preparation |
| `test_playable.mpg` | 320×240 MPEG-1 video in an MPEG program stream, 25 frames at 25 fps | Real MPG preflight and playback-composition preparation |
| `test_playable.mpeg` | 320×240 MPEG-2 video in an MPEG program stream, 25 frames at 25 fps | Real MPEG preflight and playback-composition preparation |
| `test_playable.m2v` | 320×240 MPEG-2 elementary video stream, 25 frames at 25 fps | Real M2V preflight, including AVFoundation precise-timing regression coverage |
| `test_playable.ts` | 320×180 H.264 in 188-byte MPEG-TS packets, 25 frames at 25 fps | Real TS preflight and playback-composition preparation |
| `test_playable.mts` | 320×180 H.264 in 192-byte M2TS packets, 25 frames at 25 fps | Real AVCHD-style MTS preflight and playback-composition preparation |
| `test_playable.m2ts` | 320×180 H.264 in 192-byte M2TS packets, 25 frames at 25 fps | Real M2TS preflight and playback-composition preparation |
| `test_playable.3gp` | 64×64 H.264 test pattern, four frames at 6 fps in a 3GPP container | Real 3GP preflight and playback-composition preparation |
| `test_playable.3g2` | 64×64 H.264 test pattern, four frames at 6 fps in a 3GPP2 container | Real 3G2 preflight and playback-composition preparation |
| `test_vp8_alpha_vorbis.webm` | 96×64 VP8, 12 frames with `AlphaMode=1`, plus 48 kHz mono Vorbis; SHA-256 `0c85d48cb2d269d2886616d9989b0379a9d6cd9234902d895738436b30a40fa5` | Transparent VP8 probe, alpha preparation, and optional-audio mapping |
| `test_vp9_alpha_opus.webm` | 96×64 VP9, 12 frames with `AlphaMode=1`, plus 48 kHz mono Opus; SHA-256 `28673cb1a7280a5ab915ac2349c9bbf5882e3713424584fa659bcc849a325a17` | Transparent VP9 probe and Opus mapping |
| `test_vp9_alpha_no_audio.webm` | 96×64 VP9, 12 frames with `AlphaMode=1`, no audio; SHA-256 `c7ffdac44d43761f4012e56b9a90823c722009a52a2f576947371616fce901c8` | Transparent VP9 probe and optional-audio absence |

The checked-in native-container fixtures have these canonical SHA-256 values:

```text
1722e07e1333ff32dc34c6c25093de913afbcd28223d9e33110fec298c136f8d  test_playable.avi
e508c9d1ba53a3d8ed162730d460482375fb3778da58b3d313121e53a20439ea  test_playable.dv
dd70692c320bfafcd6ccbb3d27903da64d8e363ba5ffe1aad4cef037e126ef4d  test_playable.mpg
249ff5695c4d9ab2c08f3a244e57319b1561e1b24affb97519c657f2391833b1  test_playable.mpeg
5f9cd534e5119f0989abff7028c0a8dd0a73c1967100acb06827e2677f125e9b  test_playable.m2v
fbfb35c714a29a1faec53df5fce33e9dc033940c0b4e4bf720ceffd27730d0c8  test_playable.ts
bac3336199e4a6bc76b50b720276c5f5b97be69af7bd6a230020390bc8d80bed  test_playable.mts
bac3336199e4a6bc76b50b720276c5f5b97be69af7bd6a230020390bc8d80bed  test_playable.m2ts
e311892c5e072eccb668f73081858eb3b60af9605906b7835721c1c89c686c70  test_playable.3gp
d139cda9e570a18df2631e1239c4a678f44c50a69ff21f9a1d706928fb7f5686  test_playable.3g2
```

## Provenance and regeneration

Run these commands from the repository root. They are the canonical fixture
recipes. The commands for `test-video.mp4`, `test_playable.mov`,
`test_playable.m4v`, and all ten native-container fixtures are also the exact
commands used for the current files. The older fixtures predate this manifest;
their recipes reproduce the media contracts tested by the suite without
claiming byte-for-byte historical reconstruction.

The ten native-container fixtures were generated on 2026-07-28 with Homebrew
FFmpeg 7.1.1_3 using `/opt/homebrew/bin/ffmpeg`. That binary's SHA-256 was
`7697b094387e2918821fe7480c73f5d44543817096e9d5b5fafe58ecd6912569`.
The M2V fixture also captures an AVFoundation behavior: a raw MPEG-2 elementary
stream needs `AVURLAssetPreferPreciseDurationAndTimingKey` for its track format
description to load reliably. Reframer enables that option only for M2V so the
other formats keep AVURLAsset's default loading behavior.

The three WebM fixtures originated in the isolated 2026-07-28 helper
validation workspace. They were generated with Homebrew FFmpeg 7.1.1_3,
Lavc61.19.101/Lavf61.7.100, libvpx 1.15.2, Opus 1.5.2, and libvorbis 1.3.7.
The exact `/opt/homebrew/bin/ffmpeg` binary SHA-256 was
`7697b094387e2918821fe7480c73f5d44543817096e9d5b5fafe58ecd6912569`.
The exact historical commands are included below. Re-running them preserves
the decoded media contract, but does not promise byte-identical WebM files:
FFmpeg randomizes Matroska `TrackUID` values. Keep the checked-in fixture
SHA-256 values above as canonical.

Each file decodes 73,728 alpha samples: minimum 0, maximum 255, mean 127.5,
with exactly 36,864 zero samples and 36,864 samples at 255. The normalized
raw-alpha SHA-256 is
`c04eca3b362f3261a252f26aa7b0a27a0e0eb27ec4289f4a05f7ce9b22daff81`
for every fixture.

```sh
FIXTURES=Reframer/ReframerTests/TestFixtures
FFMPEG=/opt/homebrew/bin/ffmpeg

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc2=size=160x90:rate=30000/1001' \
  -frames:v 1291 -an -c:v libx264 -preset veryslow -crf 35 \
  -pix_fmt yuv420p -movflags +faststart \
  -metadata comment='Synthetic Reframer test fixture' \
  -y "$FIXTURES/test-video.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc=size=1920x1080:rate=30:duration=2' \
  -c:v libx264 -pix_fmt yuv420p \
  -y "$FIXTURES/test_30fps_2s.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc=size=1920x1080:rate=60:duration=5' \
  -c:v libx264 -pix_fmt yuv420p \
  -y "$FIXTURES/test_60fps_5s.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc=size=640x480:rate=30:duration=1' \
  -c:v libx264 -pix_fmt yuv420p \
  -y "$FIXTURES/test_4x3_1s.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc2=size=64x64:rate=24000/1001' \
  -frames:v 24 -c:v libx264 -preset veryfast -crf 35 \
  -pix_fmt yuv420p -movflags +faststart \
  -y "$FIXTURES/test_23976fps_24f.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc2=size=64x64:rate=60000/1001' \
  -frames:v 60 -c:v libx264 -preset veryfast -crf 35 \
  -pix_fmt yuv420p -movflags +faststart \
  -y "$FIXTURES/test_5994fps_60f.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc2=size=64x64:rate=20' \
  -vf "select='lte(n,10)*not(mod(n,2))+between(n,11,15)'" \
  -frames:v 11 -fps_mode vfr \
  -c:v libx264 -preset veryfast -crf 35 \
  -pix_fmt yuv420p -movflags +faststart \
  -y "$FIXTURES/test_vfr_11f.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=0.2' \
  -c:a aac -b:a 32k -movflags +faststart \
  -y "$FIXTURES/test_audio_only.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc2=size=64x64:rate=30' \
  -frames:v 6 -an -c:v libx264 -preset veryslow -crf 35 \
  -pix_fmt yuv420p -movflags +faststart \
  -metadata comment='Synthetic Reframer test fixture' \
  -f mov -y "$FIXTURES/test_playable.mov"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc2=size=64x64:rate=30' \
  -frames:v 6 -an -c:v libx264 -preset veryslow -crf 35 \
  -pix_fmt yuv420p -movflags +faststart \
  -metadata comment='Synthetic Reframer test fixture' \
  -f mp4 -y "$FIXTURES/test_playable.m4v"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=64x64:rate=6' \
  -frames:v 4 -an -c:v mjpeg -q:v 10 -pix_fmt yuvj420p \
  -f avi "$FIXTURES/test_playable.avi"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=720x480:rate=30000/1001' \
  -frames:v 2 -an -c:v dvvideo -pix_fmt yuv411p \
  -f dv "$FIXTURES/test_playable.dv"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=320x240:rate=25' \
  -frames:v 25 -an -c:v mpeg1video -q:v 12 \
  -f mpeg "$FIXTURES/test_playable.mpg"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=320x240:rate=25' \
  -frames:v 25 -an -c:v mpeg2video -q:v 12 \
  -f mpeg "$FIXTURES/test_playable.mpeg"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=320x240:rate=25' \
  -frames:v 25 -an -c:v mpeg2video -q:v 12 \
  -f mpeg2video "$FIXTURES/test_playable.m2v"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=320x180:rate=25' \
  -frames:v 25 -an -c:v libx264 -profile:v high -level:v 4.0 \
  -preset veryfast -crf 35 -pix_fmt yuv420p \
  -f mpegts "$FIXTURES/test_playable.ts"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=320x180:rate=25' \
  -frames:v 25 -an -c:v libx264 -profile:v high -level:v 4.0 \
  -preset veryfast -crf 35 -pix_fmt yuv420p -mpegts_m2ts_mode 1 \
  -f mpegts "$FIXTURES/test_playable.mts"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=320x180:rate=25' \
  -frames:v 25 -an -c:v libx264 -profile:v high -level:v 4.0 \
  -preset veryfast -crf 35 -pix_fmt yuv420p -mpegts_m2ts_mode 1 \
  -f mpegts "$FIXTURES/test_playable.m2ts"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=64x64:rate=6' \
  -frames:v 4 -an -c:v libx264 -profile:v baseline -level:v 3.0 \
  -preset veryfast -crf 35 -pix_fmt yuv420p -movflags +faststart \
  -f 3gp "$FIXTURES/test_playable.3gp"

"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=64x64:rate=6' \
  -frames:v 4 -an -c:v libx264 -profile:v baseline -level:v 3.0 \
  -preset veryfast -crf 35 -pix_fmt yuv420p -movflags +faststart \
  -f 3g2 "$FIXTURES/test_playable.3g2"

# Exact VP9 + Opus historical command.
/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y \
  -f lavfi \
  -i "color=c=red@0.0:s=96x64:r=12:d=1,format=yuva420p,drawbox=x=48:y=0:w=48:h=64:color=red@1.0:t=fill:replace=1" \
  -f lavfi -i "sine=frequency=660:sample_rate=48000:duration=1" \
  -map 0:v:0 -map 1:a:0 \
  -c:v libvpx-vp9 -lossless 1 -pix_fmt yuva420p -auto-alt-ref 0 \
  -c:a libopus -b:a 64k \
  "$FIXTURES/test_vp9_alpha_opus.webm"

# Exact VP8 + Vorbis historical command.
/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y \
  -f lavfi \
  -i "color=c=blue@0.0:s=96x64:r=12:d=1,format=yuva420p,drawbox=x=48:y=0:w=48:h=64:color=blue@1.0:t=fill:replace=1" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=1" \
  -map 0:v:0 -map 1:a:0 \
  -c:v libvpx -lossless 1 -pix_fmt yuva420p -auto-alt-ref 0 \
  -c:a libvorbis -q:a 4 \
  "$FIXTURES/test_vp8_alpha_vorbis.webm"

# Exact no-audio derivative.
/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y \
  -i "$FIXTURES/test_vp9_alpha_opus.webm" \
  -map 0:v:0 -c copy \
  "$FIXTURES/test_vp9_alpha_no_audio.webm"
```

Record the tool versions and inspect the resulting media with:

```sh
ffmpeg -version
ffprobe -version

for file in \
  "$FIXTURES"/*.mp4 \
  "$FIXTURES"/test_playable.* \
  "$FIXTURES"/*.webm; do
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,r_frame_rate,avg_frame_rate,nb_frames \
    -show_entries format=format_name,duration,size:format_tags=comment \
    -of compact=p=0:nk=0 "$file"
done

ffprobe -v error -select_streams v:0 -show_frames \
  -show_entries frame=best_effort_timestamp_time \
  -of csv=p=0 "$FIXTURES/test_vfr_11f.mp4"
```
