#!/bin/bash

set -euo pipefail

HELPER_PATH="${1:-}"
SOURCE_RECORD="${2:-}"
REQUIRE_RECORDED_SHA="${REQUIRE_RECORDED_SHA:-0}"

if [ -z "$HELPER_PATH" ] || [ ! -x "$HELPER_PATH" ]; then
    echo "usage: $0 /path/to/reframer-ffmpeg [SOURCE.md]" >&2
    exit 64
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reframer-helper-validation.XXXXXX")"
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

ARCHITECTURES="$(
    /usr/bin/lipo -archs "$HELPER_PATH" |
        tr ' ' '\n' |
        sed '/^$/d' |
        LC_ALL=C sort |
        tr '\n' ' ' |
        sed 's/ $//'
)"
if [ "$ARCHITECTURES" != "arm64 x86_64" ]; then
    echo "error: WebM helper architectures are not exactly arm64 and x86_64: $ARCHITECTURES" >&2
    exit 65
fi

for architecture in arm64 x86_64; do
    THIN_HELPER="$TEMP_DIR/reframer-ffmpeg-$architecture"
    CONFIGURATION_FILE="$TEMP_DIR/configuration-$architecture.txt"
    STRINGS_FILE="$TEMP_DIR/strings-$architecture.txt"
    /usr/bin/lipo "$HELPER_PATH" -thin "$architecture" -output "$THIN_HELPER"
    /usr/bin/strings "$THIN_HELPER" >"$STRINGS_FILE"
    /usr/bin/awk \
        '/^--prefix=.*--disable-network/ && !found { print; found = 1 }' \
        "$STRINGS_FILE" >"$CONFIGURATION_FILE"
    if [ ! -s "$CONFIGURATION_FILE" ]; then
        echo "error: $architecture helper does not expose its FFmpeg -version configuration" >&2
        exit 65
    fi
    if ! /usr/bin/grep -Fiq "ffmpeg version 8.1.2" "$STRINGS_FILE"; then
        echo "error: $architecture helper is not FFmpeg 8.1.2" >&2
        exit 65
    fi
done

/usr/bin/python3 - \
    "$TEMP_DIR/configuration-arm64.txt" \
    "$TEMP_DIR/configuration-x86_64.txt" <<'PY'
import shlex
import sys

required = {
    "--disable-everything",
    "--enable-ffmpeg",
    "--disable-ffplay",
    "--disable-ffprobe",
    "--disable-avdevice",
    "--disable-network",
    "--disable-autodetect",
    "--disable-gpl",
    "--disable-nonfree",
    "--disable-version3",
    "--enable-static",
    "--disable-shared",
    "--enable-libvpx",
    "--enable-protocol=file",
    "--enable-protocol=pipe",
    "--enable-demuxer=matroska",
    "--enable-muxer=mov",
    "--enable-decoder=libvpx_vp8",
    "--enable-decoder=libvpx_vp9",
    "--enable-decoder=opus",
    "--enable-decoder=vorbis",
    "--enable-encoder=prores_ks",
    "--enable-encoder=pcm_s16le",
}
forbidden = {
    "--enable-network",
    "--enable-gpl",
    "--enable-nonfree",
    "--enable-version3",
}


def parse(path: str, architecture: str) -> tuple[set[str], set[str]]:
    configuration = open(path, encoding="utf-8").read().strip()
    options = shlex.split(configuration)
    option_set = set(options)

    missing = required - option_set
    if missing:
        raise SystemExit(
            f"error: {architecture} helper is missing required configuration: "
            f"{sorted(missing)}"
        )
    present_forbidden = forbidden & option_set
    if present_forbidden:
        raise SystemExit(
            f"error: {architecture} helper enables prohibited configuration: "
            f"{sorted(present_forbidden)}"
        )

    exact_feature_families = {
        "--enable-protocol=": {"--enable-protocol=file", "--enable-protocol=pipe"},
        "--enable-demuxer=": {"--enable-demuxer=matroska"},
        "--enable-muxer=": {"--enable-muxer=mov"},
    }
    for prefix, expected in exact_feature_families.items():
        actual = {option for option in option_set if option.startswith(prefix)}
        if actual != expected:
            raise SystemExit(
                f"error: {architecture} helper {prefix} surface is {sorted(actual)}, "
                f"expected {sorted(expected)}"
            )

    architecture_value = f"--arch={architecture}"
    if architecture_value not in option_set:
        raise SystemExit(
            f"error: {architecture} helper configuration omits {architecture_value}"
        )

    normalized = {
        option
        for option in option_set
        if not option.startswith(
            (
                "--prefix=",
                "--arch=",
                "--extra-cflags=",
                "--extra-cxxflags=",
                "--extra-ldflags=",
                "--x86asmexe=",
            )
        )
    }
    return option_set, normalized


_, arm = parse(sys.argv[1], "arm64")
_, intel = parse(sys.argv[2], "x86_64")
if arm != intel:
    raise SystemExit(
        "error: helper slices differ after normalizing build-root, architecture, "
        "compiler-flag, and x86asmexe paths"
    )
PY

if [ "$REQUIRE_RECORDED_SHA" = "1" ]; then
    if [ -z "$SOURCE_RECORD" ] || [ ! -f "$SOURCE_RECORD" ]; then
        echo "error: SOURCE.md is required for the checked-in helper SHA gate" >&2
        exit 65
    fi
    ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$HELPER_PATH" | awk '{print $1}')"
    RECORDED_SHA="$(
        /usr/bin/python3 - "$SOURCE_RECORD" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(
    r"checked-in pre-release-signing helper SHA-256 is:\s*\n+\s*"
    r"`([0-9a-f]{64})`",
    text,
    re.IGNORECASE,
)
print(match.group(1).lower() if match else "")
PY
    )"
    if [ -z "$RECORDED_SHA" ] || [ "$ACTUAL_SHA" != "$RECORDED_SHA" ]; then
        echo "error: checked-in WebM helper SHA-256 does not match SOURCE.md" >&2
        echo "actual:   $ACTUAL_SHA" >&2
        echo "recorded: $RECORDED_SHA" >&2
        exit 65
    fi
fi

echo "WebM helper provenance passed: FFmpeg 8.1.2, $ARCHITECTURES"
