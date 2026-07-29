#!/bin/bash

set -euo pipefail

readonly FFMPEG_VERSION="8.1.2"
readonly FFMPEG_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
readonly FFMPEG_SIGNING_FINGERPRINT="FCF986EA15E6E293A5644F10B4322F04D67658D8"
readonly LIBVPX_TAG="v1.16.0"
readonly LIBVPX_TAG_OBJECT="04def0a07f8bfa95785e30e6db95036cda17f9b2"
readonly LIBVPX_COMMIT="1024874c5919305883187e2953de8fcb4c3d7fa6"
readonly NASM_VERSION="2.16.03"
readonly NASM_SHA256="1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148"
readonly DEPLOYMENT_TARGET="15.0"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: the Reframer media helper must be built on macOS" >&2
  exit 1
fi

for command in clang codesign curl git gpg lipo make shasum tar xcrun; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: required command is unavailable: $command" >&2
    exit 1
  fi
done

destination="${1:-}"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/reframer-media-helper.XXXXXX")"
cleanup() {
  if [ "${KEEP_BUILD_ROOT:-0}" = "1" ]; then
    echo "Preserved build root: $build_root"
  else
    rm -rf "$build_root"
  fi
}
trap cleanup EXIT

downloads="$build_root/downloads"
prefix="$build_root/prefix"
dist="$build_root/dist"
mkdir -p "$downloads" "$prefix/tools" "$dist/universal"

download() {
  local url="$1"
  local output="$2"
  curl --fail --location --proto '=https' --tlsv1.2 \
    --retry 3 --output "$output" "$url"
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "error: SHA-256 mismatch for $file" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

ffmpeg_archive="$downloads/ffmpeg-$FFMPEG_VERSION.tar.xz"
ffmpeg_signature="$ffmpeg_archive.asc"
ffmpeg_key="$downloads/ffmpeg-devel.asc"
nasm_archive="$downloads/nasm-$NASM_VERSION.tar.xz"

download \
  "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" \
  "$ffmpeg_archive"
download \
  "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz.asc" \
  "$ffmpeg_signature"
download "https://ffmpeg.org/ffmpeg-devel.asc" "$ffmpeg_key"
download \
  "https://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.xz" \
  "$nasm_archive"

verify_sha256 "$ffmpeg_archive" "$FFMPEG_SHA256"
verify_sha256 "$nasm_archive" "$NASM_SHA256"

gnupg_home="$build_root/gnupg"
mkdir -m 700 "$gnupg_home"
GNUPGHOME="$gnupg_home" gpg --batch --import "$ffmpeg_key" >/dev/null
imported_fingerprint="$(
  GNUPGHOME="$gnupg_home" gpg --batch --with-colons --fingerprint |
    awk -F: '$1 == "fpr" {print $10; exit}'
)"
if [ "$imported_fingerprint" != "$FFMPEG_SIGNING_FINGERPRINT" ]; then
  echo "error: unexpected FFmpeg signing-key fingerprint" >&2
  exit 1
fi
GNUPGHOME="$gnupg_home" gpg --batch --verify \
  "$ffmpeg_signature" "$ffmpeg_archive"

tar -xf "$ffmpeg_archive" -C "$build_root"
tar -xf "$nasm_archive" -C "$build_root"

git clone --quiet \
  --branch "$LIBVPX_TAG" \
  --single-branch \
  https://chromium.googlesource.com/webm/libvpx \
  "$build_root/libvpx-$LIBVPX_TAG"

actual_tag_object="$(
  git -C "$build_root/libvpx-$LIBVPX_TAG" rev-parse "$LIBVPX_TAG"
)"
actual_commit="$(
  git -C "$build_root/libvpx-$LIBVPX_TAG" rev-parse "$LIBVPX_TAG^{}"
)"
if [ "$actual_tag_object" != "$LIBVPX_TAG_OBJECT" ] ||
   [ "$actual_commit" != "$LIBVPX_COMMIT" ]; then
  echo "error: libvpx tag or commit does not match the pinned source" >&2
  exit 1
fi

(
  cd "$build_root/nasm-$NASM_VERSION"
  ./configure --prefix="$prefix/tools"
  make -j"$(sysctl -n hw.logicalcpu)"
  make install
)

common_vpx=(
  --disable-examples
  --disable-tools
  --disable-docs
  --disable-unit-tests
  --disable-vp8-encoder
  --disable-vp9-encoder
  --enable-vp9-highbitdepth
  --enable-pic
  --enable-small
)

build_vpx() {
  local arch="$1"
  local target="$2"
  local build_dir="$build_root/vpx-build-$arch"
  mkdir -p "$build_dir"
  (
    cd "$build_dir"
    export PATH="$prefix/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    "$build_root/libvpx-$LIBVPX_TAG/configure" \
      --target="$target" \
      --prefix="$prefix/$arch" \
      --extra-cflags="-arch $arch -mmacosx-version-min=$DEPLOYMENT_TARGET" \
      --extra-cxxflags="-arch $arch -mmacosx-version-min=$DEPLOYMENT_TARGET" \
      "${common_vpx[@]}"
    make -j"$(sysctl -n hw.logicalcpu)"
    make install
  )
}

build_vpx arm64 arm64-darwin25-gcc
build_vpx x86_64 x86_64-darwin25-gcc

common_ffmpeg=(
  --disable-everything
  --enable-ffmpeg
  --disable-ffplay
  --disable-ffprobe
  --disable-avdevice
  --disable-doc
  --disable-debug
  --disable-network
  --disable-autodetect
  --disable-gpl
  --disable-nonfree
  --disable-version3
  --enable-small
  --enable-static
  --disable-shared
  --enable-pthreads
  --enable-libvpx
  --enable-avcodec
  --enable-avformat
  --enable-avfilter
  --enable-swscale
  --enable-swresample
  --enable-protocol=file
  --enable-protocol=pipe
  --enable-demuxer=matroska
  --enable-muxer=mov
  --enable-decoder=libvpx_vp8
  --enable-decoder=libvpx_vp9
  --enable-decoder=opus
  --enable-decoder=vorbis
  --enable-encoder=prores_ks
  --enable-encoder=pcm_s16le
  --enable-parser=vp8
  --enable-parser=vp9
  --enable-parser=opus
  --enable-parser=vorbis
  --enable-filter=scale
  --enable-filter=format
  --enable-filter=aresample
  --enable-filter=aformat
  --enable-filter=split
  --enable-filter=alphaextract
  --enable-filter=setrange
  --enable-filter=mergeplanes
)

build_ffmpeg() {
  local arch="$1"
  local build_dir="$build_root/ffmpeg-build-$arch"
  mkdir -p "$build_dir"
  (
    cd "$build_dir"
    export PATH="$prefix/tools/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export PKG_CONFIG_PATH="$prefix/$arch/lib/pkgconfig"
    export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    "$build_root/ffmpeg-$FFMPEG_VERSION/configure" \
      --prefix="$dist/$arch" \
      --arch="$arch" \
      --target-os=darwin \
      --cc=/usr/bin/clang \
      --extra-cflags="-arch $arch -mmacosx-version-min=$DEPLOYMENT_TARGET" \
      --extra-ldflags="-arch $arch -mmacosx-version-min=$DEPLOYMENT_TARGET" \
      --x86asmexe="$prefix/tools/bin/nasm" \
      --pkg-config-flags=--static \
      "${common_ffmpeg[@]}"
    make -j"$(sysctl -n hw.logicalcpu)"
    make install
  )
}

build_ffmpeg arm64
build_ffmpeg x86_64

helper="$dist/universal/reframer-ffmpeg"
lipo -create \
  "$dist/arm64/bin/ffmpeg" \
  "$dist/x86_64/bin/ffmpeg" \
  -output "$helper"
codesign --force --sign - --timestamp=none --options runtime \
  --identifier com.reframer.app.ffmpeg "$helper"

echo "Built: $helper"
file "$helper"
shasum -a 256 "$helper"

if [ -n "$destination" ]; then
  mkdir -p "$(dirname "$destination")"
  cp "$helper" "$destination"
  chmod 755 "$destination"
  echo "Copied helper to: $destination"
fi
