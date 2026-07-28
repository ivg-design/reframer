# Reframer test-video fixtures

Every media file in this directory is synthetic. The video fixtures use
FFmpeg `lavfi` test patterns, and the audio-only fixture uses a generated sine
wave. They contain no third-party footage, recorded voices, or user media.

The checked-in files were generated or verified with FFmpeg 7.1.1
(`Lavf61.7.100`, `Lavc61.19.101`) and libx264. Tests assert media semantics
such as container acceptance, frame count, presentation timestamps, and aspect
ratio. Encoder and muxer versions can change the encoded bytes, so SHA hashes
are not expected to be stable across FFmpeg/libx264 versions.

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

## Provenance and regeneration

Run these commands from the repository root. They are the canonical fixture
recipes. The three commands for `test-video.mp4`, `test_playable.mov`, and
`test_playable.m4v` are also the exact commands used for the current files.
The older fixtures predate this manifest; their recipes reproduce the media
contracts tested by the suite without claiming byte-for-byte historical
reconstruction.

```sh
FIXTURES=Reframer/ReframerTests/TestFixtures

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
```

Record the tool versions and inspect the resulting media with:

```sh
ffmpeg -version
ffprobe -version

for file in "$FIXTURES"/*.mp4 "$FIXTURES"/*.mov "$FIXTURES"/*.m4v; do
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,r_frame_rate,avg_frame_rate,nb_frames \
    -show_entries format=format_name,duration,size:format_tags=comment \
    -of compact=p=0:nk=0 "$file"
done

ffprobe -v error -select_streams v:0 -show_frames \
  -show_entries frame=best_effort_timestamp_time \
  -of csv=p=0 "$FIXTURES/test_vfr_11f.mp4"
```
