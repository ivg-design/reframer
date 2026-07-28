#!/usr/bin/env python3

"""Validate release metadata and public claims against one product contract."""

from __future__ import annotations

import json
import plistlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CONTRACT_PATH = ROOT / "docs" / "product-contract.json"
PROJECT_PATH = ROOT / "Reframer" / "Reframer.xcodeproj" / "project.pbxproj"
INFO_PATH = ROOT / "Reframer" / "Reframer" / "Resources" / "Info.plist"
ENTITLEMENTS_PATH = (
    ROOT / "Reframer" / "Reframer" / "Resources" / "Reframer.entitlements"
)

PUBLIC_DOCUMENTS = (
    ROOT / "CHANGELOG.md",
    ROOT / "README.md",
    ROOT / "SECURITY.md",
    ROOT / "Reframer" / "README.md",
    ROOT / "docs" / "FEATURES.md",
    ROOT / "docs" / "FEATURE_TESTS.md",
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

    privacy = contract["privacy"]
    if privacy.get("appSandbox") is not True:
        fail("product contract must require App Sandbox")
    if privacy.get("userSelectedFileAccess") != "read-only":
        fail("product contract must allow only user-selected read-only files")

    if re.fullmatch(r"\d+\.\d+\.\d+", version) is None:
        fail(f"contract version is not semantic: {version}")

    project = PROJECT_PATH.read_text(encoding="utf-8")
    project_versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", project))
    if project_versions != {version}:
        fail(f"project versions {sorted(project_versions)} do not equal {version}")

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
    )
    for claim in required_claims:
        if claim not in combined:
            fail(f"public documentation does not contain required claim: {claim}")

    print(
        f"Product contract passed: Reframer {version}, "
        f"macOS {minimum_macos}+, {bundle_identifier}"
    )


if __name__ == "__main__":
    main()
