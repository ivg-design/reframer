#!/usr/bin/env python3

"""Validate release metadata and public claims against one product contract."""

from __future__ import annotations

import json
import plistlib
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Optional
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
CONTRACT_PATH = ROOT / "docs" / "product-contract.json"
PROJECT_PATH = ROOT / "Reframer" / "Reframer.xcodeproj" / "project.pbxproj"
INFO_PATH = ROOT / "Reframer" / "Reframer" / "Resources" / "Info.plist"
HELP_ROOT = ROOT / "Reframer" / "Reframer" / "Reframer.help"
HELP_INFO_PATH = HELP_ROOT / "Contents" / "Info.plist"
HELP_LOCALIZED_ROOT = HELP_ROOT / "Contents" / "Resources" / "en.lproj"
LICENSE_PATH = ROOT / "LICENSE"
ENTITLEMENTS_PATH = (
    ROOT / "Reframer" / "Reframer" / "Resources" / "Reframer.entitlements"
)
SHORTCUT_SOURCE_PATH = (
    ROOT / "Reframer" / "Reframer" / "Models" / "ShortcutSettings.swift"
)
APP_DELEGATE_PATH = ROOT / "Reframer" / "Reframer" / "App" / "AppDelegate.swift"

SHORTCUT_DOCUMENTS = (
    ROOT / "README.md",
    ROOT / "docs" / "PRODUCT_CONTRACT.md",
    ROOT
    / "Reframer"
    / "Reframer"
    / "Reframer.docc"
    / "Articles"
    / "KeyboardShortcuts.md",
    ROOT
    / "Reframer"
    / "Reframer"
    / "Reframer.help"
    / "Contents"
    / "Resources"
    / "en.lproj"
    / "shortcuts.html",
)

PUBLIC_DOCUMENTS = (
    ROOT / "CHANGELOG.md",
    ROOT / "README.md",
    ROOT / "SECURITY.md",
    ROOT / "Reframer" / "README.md",
    ROOT / "docs" / "FEATURES.md",
    ROOT / "docs" / "FEATURE_TESTS.md",
    ROOT / "docs" / "AUDIT_2026-07-28.md",
    ROOT / "docs" / "PRODUCT_CONTRACT.md",
    ROOT / "docs" / "RELEASE.md",
    ROOT / "docs" / "THREAT_MODEL.md",
    ROOT / "Reframer" / "CHANGELOG.md",
)

PUBLIC_DOCUMENT_ROOTS = (
    ROOT / "Reframer" / "Reframer" / "Reframer.docc",
    ROOT / "Reframer" / "Reframer" / "Reframer.help",
)

STALE_CLAIMS = {
    "libmpv": "third-party codec installation is not part of the product",
    "youtube": "URL streaming is not implemented",
    "webm": "WebM is not in the supported container contract",
    "mkv": "Matroska is not in the supported container contract",
    "macos 14": "the deployment target is macOS 15.0",
    "global shortcuts require the normal macos privacy": (
        "registered hot keys require no Accessibility or Input Monitoring permission"
    ),
    "grant accessibility access": (
        "global shortcuts no longer use Accessibility permission"
    ),
}


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_public_texts() -> list[tuple[Path, str]]:
    documents: list[Path] = list(PUBLIC_DOCUMENTS)
    for root in PUBLIC_DOCUMENT_ROOTS:
        documents.extend(path for path in root.rglob("*") if path.suffix in {".md", ".html"})

    texts: list[tuple[Path, str]] = []
    for path in documents:
        if not path.is_file():
            fail(f"required public document is missing: {path.relative_to(ROOT)}")
        texts.append((path, path.read_text(encoding="utf-8")))
    return texts


def normalized_prose(text: str) -> str:
    """Make Markdown and simple Help HTML comparable without an HTML parser."""
    without_tags = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", without_tags).strip().lower()


class HelpLinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.targets: list[str] = []

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, Optional[str]]],
    ) -> None:
        for name, value in attrs:
            if name in {"href", "src"} and value:
                self.targets.append(value)


def validate_relative_target(source: Path, raw_target: str) -> None:
    target = raw_target.strip()
    if target.startswith("<") and ">" in target:
        target = target[1 : target.index(">")]
    elif " " in target:
        target = target.split(maxsplit=1)[0]

    target = unquote(target)
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or target.startswith(("#", "<doc:")):
        return

    relative_path = parsed.path
    if not relative_path:
        return

    resolved = (source.parent / relative_path).resolve()
    if not resolved.exists():
        fail(
            f"{source.relative_to(ROOT)} links to missing path "
            f"{raw_target!r}"
        )


def validate_public_links(public_texts: list[tuple[Path, str]]) -> None:
    link_documents = dict(public_texts)
    archive_root = ROOT / "docs" / "archive"
    for path in ROOT.rglob("*.md"):
        if path.is_relative_to(archive_root):
            continue
        link_documents.setdefault(path, path.read_text(encoding="utf-8"))

    for path, text in link_documents.items():
        if path.suffix == ".md":
            for target in re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", text):
                validate_relative_target(path, target)
        elif path.suffix == ".html":
            parser = HelpLinkParser()
            parser.feed(text)
            for target in parser.targets:
                validate_relative_target(path, target)


def validate_shortcut_surfaces() -> None:
    for path in SHORTCUT_DOCUMENTS:
        if not path.is_file():
            fail(f"required shortcut document is missing: {path.relative_to(ROOT)}")

        prose = normalized_prose(path.read_text(encoding="utf-8"))
        if re.search(r"forward.{0,100}page down", prose) is None:
            fail(
                f"{path.relative_to(ROOT)} does not state that Page Down "
                "moves forward"
            )
        if re.search(r"backward.{0,100}page up", prose) is None:
            fail(
                f"{path.relative_to(ROOT)} does not state that Page Up "
                "moves backward"
            )

        required_lifecycle_terms = (
            "registered",
            "loaded",
            "locked",
            "navigation",
        )
        for term in required_lifecycle_terms:
            if term not in prose:
                fail(
                    f"{path.relative_to(ROOT)} omits shortcut lifecycle term: "
                    f"{term}"
                )

        accessibility_index = prose.find("accessibility")
        input_monitoring_index = prose.find("input monitoring")
        if accessibility_index < 0 or input_monitoring_index < 0:
            fail(
                f"{path.relative_to(ROOT)} omits the global-shortcut "
                "permission contract"
            )
        permission_span = prose[
            max(0, min(accessibility_index, input_monitoring_index) - 80):
            max(accessibility_index, input_monitoring_index) + 120
        ]
        if not any(
            denial in permission_span
            for denial in (
                "neither accessibility",
                "no accessibility",
                "without accessibility",
                "not require accessibility",
                "accessibility or input monitoring permission are not required",
            )
        ):
            fail(
                f"{path.relative_to(ROOT)} does not clearly deny an "
                "Accessibility/Input Monitoring requirement"
            )


def validate_shortcut_implementation(contract: dict[str, object]) -> None:
    frame_step = contract["playback"]["frameStep"]
    expected_frame_step = {
        "forward": "Page Down",
        "backward": "Page Up",
        "multiplier": 10,
    }
    if frame_step != expected_frame_step:
        fail(f"frame-step contract is not canonical: {frame_step}")

    global_shortcuts = contract["globalShortcuts"]
    expected_global_values = {
        "toggleLock": "Command-Shift-L",
        "stepForward": "Command-Page Down",
        "stepBackward": "Command-Page Up",
        "stepMultiplier": 10,
        "frameStepRegistration": "Registered only while frame stepping is actionable",
        "inactiveFrameStepHandling": (
            "Not registered, received, or swallowed through Reframer's "
            "global path while another app is active"
        ),
    }
    for key, expected in expected_global_values.items():
        if global_shortcuts.get(key) != expected:
            fail(
                f"global shortcut contract {key!r} is "
                f"{global_shortcuts.get(key)!r}, expected {expected!r}"
            )

    shortcut_source = SHORTCUT_SOURCE_PATH.read_text(encoding="utf-8")
    source_defaults = dict(
        re.findall(
            r"\.(frameStepForward|frameStepBackward):\s*Binding"
            r"\(shortcut:\s*Shortcut\(\s*"
            r"keyCode:\s*KeyCode\.(pageDown|pageUp),",
            shortcut_source,
        )
    )
    expected_source_defaults = {
        "frameStepForward": "pageDown",
        "frameStepBackward": "pageUp",
    }
    if source_defaults != expected_source_defaults:
        fail(
            "Swift shortcut defaults do not match the product contract: "
            f"{source_defaults}"
        )

    app_delegate = APP_DELEGATE_PATH.read_text(encoding="utf-8")
    registration_guard = (
        "includeFrameSteps: videoState.isLocked && videoState.canNavigateFrames"
    )
    if registration_guard not in app_delegate:
        fail("frame hot keys are not registered behind the actionable-state guard")


def validate_playback_implementation(contract: dict[str, object]) -> None:
    playback = contract["playback"]
    frame_navigation = playback.get("frameNavigation", {})
    expected_sample_limit = 2_000_000
    if frame_navigation.get("maximumExactSamples") != expected_sample_limit:
        fail("exact-sample ceiling is not canonical")
    if playback.get("replacementStartsPaused") is not True:
        fail("replacement playback contract must start paused")
    if "same track" not in playback.get("trackSelection", ""):
        fail("multi-track contract must keep rendering and navigation coherent")

    timeline_source = (
        ROOT
        / "Reframer"
        / "Reframer"
        / "Utilities"
        / "VideoFrameTimeline.swift"
    ).read_text(encoding="utf-8")
    if "maximumExactSampleCount = 2_000_000" not in timeline_source:
        fail("Swift exact-sample ceiling does not match the product contract")

    video_view_source = (
        ROOT / "Reframer" / "Reframer" / "Views" / "VideoView.swift"
    ).read_text(encoding="utf-8")
    load_sequence = re.search(
        r"func loadVideo\(url: URL\).*?state\.cancelScrubbing\(\)"
        r".*?state\.isPlaying = false.*?cleanup\(\)",
        video_view_source,
        flags=re.DOTALL,
    )
    if load_sequence is None:
        fail("replacement load does not clear playback before teardown")
    if "alignVideoTrackSelection(for: item)" not in video_view_source:
        fail("AVPlayerItem is not aligned to the selected metadata track")


def main() -> None:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    product = contract["product"]

    version = product["version"]
    minimum_macos = product["minimumMacOS"]
    bundle_identifier = product["bundleIdentifier"]

    global_shortcuts = contract["globalShortcuts"]
    if (
        global_shortcuts.get("observesUnregisteredKeys") is not False
        or global_shortcuts.get("requiresAccessibilityPermission") is not False
        or global_shortcuts.get("requiresInputMonitoringPermission") is not False
    ):
        fail("global shortcut privacy contract must prohibit broad key observation")
    validate_shortcut_implementation(contract)

    privacy = contract["privacy"]
    if privacy.get("appSandbox") is not True:
        fail("product contract must require App Sandbox")
    if privacy.get("userSelectedFileAccess") != "read-only":
        fail("product contract must allow only user-selected read-only files")

    if re.fullmatch(r"\d+\.\d+\.\d+", version) is None:
        fail(f"contract version is not semantic: {version}")
    validate_playback_implementation(contract)

    project = PROJECT_PATH.read_text(encoding="utf-8")
    project_versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", project))
    if project_versions != {version}:
        fail(f"project versions {sorted(project_versions)} do not equal {version}")

    build_versions = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", project))
    if len(build_versions) != 1 or not next(iter(build_versions)).isdigit():
        fail(f"project build versions are not one numeric value: {build_versions}")
    build_version = next(iter(build_versions))

    deployment_targets = set(re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([^;]+);", project))
    if deployment_targets != {minimum_macos}:
        fail(
            f"deployment targets {sorted(deployment_targets)} do not equal "
            f"{minimum_macos}"
        )

    with INFO_PATH.open("rb") as info_file:
        info = plistlib.load(info_file)

    if info.get("CFBundleShortVersionString") != "$(MARKETING_VERSION)":
        fail("Info.plist must derive its version from MARKETING_VERSION")
    if info.get("CFBundleVersion") != "$(CURRENT_PROJECT_VERSION)":
        fail("Info.plist must derive its build from CURRENT_PROJECT_VERSION")
    if info.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        fail("Info.plist must derive its identifier from PRODUCT_BUNDLE_IDENTIFIER")
    expected_copyright = "Copyright © 2026 IVG Design"
    if info.get("NSHumanReadableCopyright") != expected_copyright:
        fail("Info.plist copyright does not identify IVG Design consistently")
    if "Copyright (c) 2026 IVG Design" not in LICENSE_PATH.read_text(encoding="utf-8"):
        fail("LICENSE copyright does not identify IVG Design consistently")

    with HELP_INFO_PATH.open("rb") as help_info_file:
        help_info = plistlib.load(help_info_file)
    if help_info.get("CFBundleShortVersionString") != version:
        fail("Apple Help version does not match the product version")
    if help_info.get("CFBundleVersion") != build_version:
        fail("Apple Help build does not match the product build")
    if help_info.get("CFBundleIdentifier") != "com.reframer.help":
        fail("Apple Help bundle identifier is not com.reframer.help")
    if help_info.get("HPDBookIndexPath") != "search.cshelpindex":
        fail("Apple Help must use the modern CoreSpotlight search index")
    modern_help_index = HELP_LOCALIZED_ROOT / "search.cshelpindex"
    legacy_help_index = HELP_LOCALIZED_ROOT / "search.helpindex"
    if not modern_help_index.is_file() or modern_help_index.stat().st_size == 0:
        fail("Apple Help modern search index is missing or empty")
    if legacy_help_index.exists():
        fail("Apple Help legacy search index must not remain in the product")

    if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_identifier};" not in project:
        fail(f"app bundle identifier is not {bundle_identifier}")

    sandbox_settings = set(re.findall(r"ENABLE_APP_SANDBOX = ([^;]+);", project))
    if sandbox_settings != {"YES"}:
        fail(f"App Sandbox build settings are not uniformly enabled: {sandbox_settings}")
    selected_file_settings = set(
        re.findall(r"ENABLE_USER_SELECTED_FILES = ([^;]+);", project)
    )
    if selected_file_settings != {"readonly"}:
        fail(
            "user-selected file build settings are not uniformly read-only: "
            f"{selected_file_settings}"
        )

    with ENTITLEMENTS_PATH.open("rb") as entitlement_file:
        entitlements = plistlib.load(entitlement_file)
    expected_entitlements = {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.files.user-selected.read-only": True,
    }
    if entitlements != expected_entitlements:
        fail(
            "source entitlements do not equal the sandbox allowlist: "
            f"{entitlements}"
        )

    expected_content_types = {
        document_type["contentType"]
        for document_type in contract["playback"]["documentTypes"]
    }
    declared_document_types = info.get("CFBundleDocumentTypes")
    if not isinstance(declared_document_types, list) or len(declared_document_types) != 1:
        fail("Info.plist must declare exactly one video document type")
    actual_content_types = set(
        declared_document_types[0].get("LSItemContentTypes", [])
    )
    if actual_content_types != expected_content_types:
        fail(
            "Info.plist document types "
            f"{sorted(actual_content_types)} do not equal the product contract "
            f"{sorted(expected_content_types)}"
        )
    if info.get("UTImportedTypeDeclarations"):
        fail("Info.plist must not import unsupported custom media types")

    public_texts = read_public_texts()
    validate_public_links(public_texts)
    for path, text in public_texts:
        normalized = text.lower()
        for stale_claim, reason in STALE_CLAIMS.items():
            if stale_claim in normalized:
                fail(
                    f"{path.relative_to(ROOT)} contains stale claim "
                    f"{stale_claim!r}: {reason}"
                )

    combined = "\n".join(text for _, text in public_texts)
    required_claims = (
        "macOS 15.0",
        "Command-Page Down",
        "Command-Page Up",
        "MP4",
        "M4V",
        "MOV",
        "no Accessibility or Input Monitoring permission",
        "App Sandbox",
        "2,000,000",
    )
    for claim in required_claims:
        if claim not in combined:
            fail(f"public documentation does not contain required claim: {claim}")

    validate_shortcut_surfaces()

    print(
        f"Product contract passed: Reframer {version}, "
        f"macOS {minimum_macos}+, {bundle_identifier}"
    )


if __name__ == "__main__":
    main()
