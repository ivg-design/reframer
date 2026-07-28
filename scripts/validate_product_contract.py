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
MAIN_VIEW_CONTROLLER_PATH = (
    ROOT / "Reframer" / "Reframer" / "Views" / "MainViewController.swift"
)
WINDOW_PLACEMENT_PATH = (
    ROOT / "Reframer" / "Reframer" / "Utilities" / "WindowPlacement.swift"
)
GLOBAL_HOT_KEY_PATH = (
    ROOT
    / "Reframer"
    / "Reframer"
    / "Utilities"
    / "GlobalHotKeyRegistrar.swift"
)
CONTROL_BAR_PATH = ROOT / "Reframer" / "Reframer" / "Views" / "ControlBar.swift"
VIDEO_STATE_PATH = ROOT / "Reframer" / "Reframer" / "Models" / "VideoState.swift"
DOCUMENTATION_VIEW_PATH = (
    ROOT / "Reframer" / "Reframer" / "Views" / "DocumentationView.swift"
)
WINDOW_PLACEMENT_TESTS_PATH = (
    ROOT / "Reframer" / "ReframerTests" / "WindowPlacementTests.swift"
)
CONTROL_BAR_TESTS_PATH = (
    ROOT / "Reframer" / "ReframerTests" / "ControlBarStepTests.swift"
)
SHORTCUT_TESTS_PATH = (
    ROOT / "Reframer" / "ReframerTests" / "ShortcutSettingsTests.swift"
)
INTEGRATION_TESTS_PATH = (
    ROOT / "Reframer" / "ReframerUITests" / "ReframerIntegrationTests.swift"
)
UI_TEST_CONFIG_PATH = (
    ROOT / "Reframer" / "ReframerUITests" / "UITestConfig.swift"
)
PRODUCTION_SWIFT_ROOT = ROOT / "Reframer" / "Reframer"
HELP_HOME_PATH = HELP_LOCALIZED_ROOT / "index.html"
LOCK_HELP_PATH = HELP_LOCALIZED_ROOT / "lock-mode.html"
LOCK_DOCC_PATH = (
    ROOT
    / "Reframer"
    / "Reframer"
    / "Reframer.docc"
    / "Articles"
    / "LockMode.md"
)

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

EXPECTED_CONTRACT_KEYS = {
    "schemaVersion",
    "product",
    "playback",
    "globalShortcuts",
    "overlay",
    "documentation",
    "privacy",
}

EXPECTED_OVERLAY_CONTRACT = {
    "managedWindowCount": 1,
    "windowModel": (
        "One canonical externally managed window contains the video and control bar"
    ),
    "unlockedExternalManagement": (
        "macOS and third-party window managers such as Mosaic move and resize "
        "the entire overlay"
    ),
    "layout": {
        "preferredWidth": 1060,
        "minimumWidth": 640,
        "regular": {
            "minimumWidth": 920,
            "rows": 1,
            "controlBarHeight": 48,
        },
        "compact": {
            "minimumWidth": 640,
            "maximumWidthExclusive": 920,
            "rows": 2,
            "controlBarHeight": 96,
        },
        "visibility": (
            "Every control remains visible and accessibility-reachable "
            "in both layouts"
        ),
    },
    "unlockedAlwaysOnTopPreference": (
        "Persisted preference selects floating or normal level only while unlocked"
    ),
    "lockedLevel": (
        "NSWindow.Level.statusBar above all ordinary application windows "
        "regardless of the unlocked preference"
    ),
    "lockedAbove": [
        "normal application windows",
        "floating application windows",
        "modal application windows",
        "utility application windows",
    ],
    "lockedYieldsTo": [
        "system pop-up menus",
        "system drag UI",
        "screen saver UI",
        "assistive-technology UI",
    ],
    "lockedPointerInput": (
        "The entire overlay, including video and controls, ignores pointer events"
    ),
    "lockedGeometry": "Moving and resizing are disabled",
    "unlockRecovery": (
        "The exact configured global Lock/Unlock chord restores interaction "
        "from another app; Reframer refuses lock without it and automatically "
        "unlocks if it becomes unavailable"
    ),
}

EXPECTED_DOCUMENTATION_CONTRACT = {
    "renderer": "Native AppKit attributed text rendered from bundled Help HTML",
    "bundledContentOnly": True,
    "networkAccess": False,
    "requiresNetworkEntitlement": False,
}

PUBLIC_CLAIM_MARKERS = {
    ROOT / "README.md": (
        "one canonical overlay window",
        "move and resize the complete unlocked overlay",
        "preferred 1,060-point width with one 48-point control row",
        "below 920 points the same controls reflow into two rows totaling 96 points",
        "640-point minimum width",
        "public status-bar window tier",
        "normal, floating, modal, and utility windows",
        "video and control bar pointer-transparent",
        "unless the exact configured global lock/unlock chord is registered",
        "automatically unlocks with a recovery report",
        "pop-up menus, drag ui, the screen saver, and assistive-technology windows",
        "renders the bundled help pages with native appkit",
        "does not require a network entitlement",
    ),
    ROOT / "docs" / "FEATURES.md": (
        "one canonical transparent overlay window",
        "move and resize the complete overlay while it is unlocked",
        "preferred 1,060-point width uses one 48-point control row",
        "640-point minimum through 919 points use two rows totaling 96 points",
        "every control remains visible and accessibility-reachable",
        "public status-bar window tier",
        "normal, floating, modal, and utility windows",
        "video and controls pointer-transparent",
        "pop-up menus, drag ui, the screen saver, and assistive-technology windows",
        "lock entry requires the exact configured global lock/unlock chord",
        "automatically unlocks and reports recovery guidance",
        "bundled help renders through native appkit",
        "without webkit or a network entitlement",
    ),
    ROOT / "docs" / "PRODUCT_CONTRACT.md": (
        "one canonical, externally managed",
        "must not expose a separately targetable control window",
        "moves or resizes the entire overlay",
        "preferred initial width is 1,060 points",
        "minimum supported width is 640 points",
        "at 920 points or wider",
        "two 48-point rows with a total height of 96 points",
        "no action, field, slider, status metadata, or accessibility element",
        "public `nswindow.level.statusbar` tier",
        "normal, floating, modal, and utility windows",
        "including its video and control bar, ignores pointer events",
        "exact configured global lock/unlock chord is successfully registered",
        "must immediately unlock and present the configured chord plus recovery guidance",
        "system pop-up menus, drag ui, the screen saver, and assistive-technology windows",
        "renders bundled help html as native appkit content",
        (
            "does not launch a webkit web process, fetch network content, "
            "or require a network entitlement"
        ),
    ),
    ROOT / "docs" / "FEATURE_TESTS.md": (
        "video and controls share one canonical window",
        "no separately managed control child",
        "renders known nonblank help text",
        "without requiring webkit or network access",
        "mosaic move/resize operations",
        "preferred width at 1,060 points",
        "supported minimum at 640",
        "layout breakpoint at 920",
        "48-point one-row and 96-point two-row modes",
        "exact registered-recovery prerequisite for lock entry",
        "forced unlock after recovery loss",
        "public status-bar level above all ordinary application windows",
        "critical system ui",
        "whole-overlay click-through",
    ),
    ROOT / "docs" / "RELEASE.md": (
        "macos or mosaic to move and resize the unlocked overlay",
        "one integral externally managed window",
        "one 48-point control row at 920 points and wider",
        "two rows totaling 96 points below 920 through the 640-point minimum",
        "preferred 1,060-point width",
        "configured global lock/unlock chord unavailable and confirm lock is refused",
        "automatically unlocks and reports recovery",
        "public status-bar window tier",
        "normal, floating, modal, and utility windows",
        "ignores pointer input over both video and controls",
        "system pop-up menus, drag ui, the screen saver, and assistive-technology ui",
        "known bundled content is visible in the native view",
    ),
    LOCK_DOCC_PATH: (
        "public status-bar tier above all ordinary application windows",
        "normal, floating, modal, and utility windows",
        "pointer events over the video and control bar pass",
        "entire control bar is pointer-transparent",
        "pop-up menus, drag ui, the screen saver, and assistive-technology windows",
        "refuses to enter lock unless the exact configured global lock/unlock chord",
        "automatically unlocks and reports",
        "command-shift-l",
    ),
    LOCK_HELP_PATH: (
        "complete overlay",
        "video and control bar",
        "public status-bar tier",
        "normal, floating, modal, and utility windows",
        "becomes pointer-transparent",
        "system pop-up menus, drag ui, the screen saver",
        "assistive-technology windows",
        "exact configured global lock/unlock chord is registered",
        "automatically unlocks and reports recovery",
        "global lock shortcut",
    ),
}


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate_exact_value(actual: object, expected: object, path: str) -> None:
    """Require both value and concrete JSON-derived type to match."""
    if type(actual) is not type(expected):
        fail(
            f"{path} has type {type(actual).__name__}, "
            f"expected {type(expected).__name__}"
        )

    if isinstance(expected, dict):
        actual_dict = actual
        actual_keys = set(actual_dict)
        expected_keys = set(expected)
        if actual_keys != expected_keys:
            fail(
                f"{path} keys {sorted(actual_keys)} do not equal "
                f"{sorted(expected_keys)}"
            )
        for key, expected_value in expected.items():
            validate_exact_value(
                actual_dict[key],
                expected_value,
                f"{path}.{key}",
            )
        return

    if isinstance(expected, list):
        actual_list = actual
        if len(actual_list) != len(expected):
            fail(
                f"{path} has {len(actual_list)} items, "
                f"expected {len(expected)}"
            )
        for index, expected_value in enumerate(expected):
            validate_exact_value(
                actual_list[index],
                expected_value,
                f"{path}[{index}]",
            )
        return

    if actual != expected:
        fail(f"{path} is {actual!r}, expected {expected!r}")


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


def require_source_markers(path: Path, markers: tuple[str, ...]) -> str:
    if not path.is_file():
        fail(f"required implementation source is missing: {path.relative_to(ROOT)}")
    source = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in source:
            fail(
                f"{path.relative_to(ROOT)} is missing implementation marker: "
                f"{marker}"
            )
    return source


def validate_overlay_implementation(contract: dict[str, object]) -> None:
    validate_exact_value(
        contract.get("overlay"),
        EXPECTED_OVERLAY_CONTRACT,
        "overlay",
    )

    app_delegate = require_source_markers(
        APP_DELEGATE_PATH,
        (
            "width: ControlBar.minimumWindowWidth",
            "width: ControlBar.preferredFullWidth",
            "window.contentViewController = mainViewController",
            "window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]",
            "mainViewController.onToggleLockRequest",
            "policy.apply(to: mainWindow)",
            "mainWindow.orderFrontRegardless()",
            "precondition(Thread.isMainThread)",
            "lockedWindowFrameGuard.updateLockState(",
            "lockedWindowFrameGuard.restorationFrame(",
            "let preferences = videoState.preferenceStore",
            "videoState.preferenceStore.set(",
            "LockModeRecoveryPolicy.requiresForcedUnlock(",
            "LockModeRecoveryPolicy.canToggle(",
            "globalHotKeyRegistrar?.isRegistered(",
            "guard toggleLockWithRecoveryGuard() else { return false }",
            "OverlayWindowPolicy.auxiliaryLevel(",
            "applyAuxiliaryWindowLevels(",
            "isLocked: isLocked,",
            "isAlwaysOnTop: isAlwaysOnTop",
            "orderVisibleAuxiliaryWindowsAboveOverlay()",
            "window?.order(.above, relativeTo: mainWindow.windowNumber)",
            "func applicationDidBecomeActive",
            "NSWorkspace.activeSpaceDidChangeNotification",
            "reapplyOverlayWindowPolicy()",
        ),
    )
    main_view = require_source_markers(
        MAIN_VIEW_CONTROLLER_PATH,
        (
            "view.addSubview(controlBar)",
            "videoContainerView.bottomAnchor.constraint(equalTo: controlBar.topAnchor)",
            "controlBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)",
            "controlBarHeightConstraint = controlBar.heightAnchor.constraint(",
            "controlBar.onPreferredHeightChange",
            "self.controlBarHeightConstraint.constant = height",
        ),
    )
    window_policy = require_source_markers(
        WINDOW_PLACEMENT_PATH,
        (
            "level: isLocked",
            "? .statusBar",
            ": (isAlwaysOnTop ? .floating : .normal)",
            "ignoresMouseEvents: isLocked",
            "isResizable: !isLocked",
            "isMovable: !isLocked",
            "static func auxiliaryLevel(",
            "struct LockedWindowFrameGuard: Equatable",
            "private(set) var lockedFrame: NSRect?",
            "mutating func updateLockState(",
            "func restorationFrame(for currentFrame: NSRect) -> NSRect?",
            "window.level = level",
            "window.ignoresMouseEvents = ignoresMouseEvents",
            "window.isMovable = isMovable",
            "window.styleMask.insert(.resizable)",
            "window.styleMask.remove(.resizable)",
        ),
    )
    require_source_markers(
        CONTROL_BAR_PATH,
        (
            "static let preferredFullWidth: CGFloat = 1_060",
            "static let minimumWindowWidth: CGFloat = 640",
            "static let compactLayoutBreakpoint: CGFloat = 920",
            "static let regularHeight: CGFloat = 48",
            "static let compactHeight: CGFloat = 96",
            "width < compactLayoutBreakpoint ? .compact : .regular",
            "layoutMode(for: width) == .compact ? compactHeight : regularHeight",
            "secondaryStackView = secondaryStack",
            "NSLayoutConstraint.deactivate(regularLayoutConstraints)",
            "NSLayoutConstraint.activate(compactLayoutConstraints)",
            "onPreferredHeightChange?(preferredHeight)",
        ),
    )
    require_source_markers(
        GLOBAL_HOT_KEY_PATH,
        (
            "enum LockModeRecoveryPolicy",
            "isCurrentlyLocked || isRecoveryRegistered",
            "isCurrentlyLocked && !isRecoveryRegistered",
            "func isRegistered(match: ShortcutMatch) -> Bool",
        ),
    )
    video_state = require_source_markers(
        VIDEO_STATE_PATH,
        (
            "var preferenceStore: UserDefaults",
            "private static func runtimeDefaults() -> UserDefaults",
            'environment["UITEST_MODE"] == "1"',
            'environment["UITEST_PREFERENCES_SUITE"]',
            "UserDefaults(suiteName: suiteName)",
            "return .standard",
        ),
    )
    require_source_markers(
        UI_TEST_CONFIG_PATH,
        (
            'isolatedPreferencesSuite = "com.reframer.app.uitests"',
            'app.launchEnvironment["UITEST_PREFERENCES_SUITE"]',
        ),
    )
    if "UserDefaults.standard" in app_delegate:
        fail("AppDelegate bypasses VideoState's isolated preference store")
    if "var preferenceStore: UserDefaults {\n        defaults\n    }" not in video_state:
        fail("VideoState.preferenceStore does not expose its selected runtime store")

    require_source_markers(
        WINDOW_PLACEMENT_TESTS_PATH,
        (
            "func testOverlayPolicyMatrix()",
            "level: .statusBar",
            "func testLockedLevelCoversApplicationWindowsButYieldsToSystemUI()",
            "NSWindow.Level.floating.rawValue",
            "NSWindow.Level.modalPanel.rawValue",
            "NSWindow.Level.popUpMenu.rawValue",
            "NSWindow.Level.screenSaver.rawValue",
            "OverlayWindowPolicy.auxiliaryLevel(",
            "func testLockedFrameGuardRejectsMoveAndResizeUntilUnlock()",
            "LockedWindowFrameGuard()",
            "func testVideoAndControlsShareOneCanonicalWindow()",
        ),
    )
    require_source_markers(
        CONTROL_BAR_TESTS_PATH,
        (
            "func testResponsiveLayoutContractUsesRegularAndCompactHeights()",
            "XCTAssertEqual(ControlBar.preferredFullWidth, 1_060)",
            "XCTAssertEqual(ControlBar.minimumWindowWidth, 640)",
            "XCTAssertEqual(ControlBar.compactLayoutBreakpoint, 920)",
            "func testRegularPreferredWidthContainsEveryControlWithVolumeVisible()",
            "func testCompactMinimumWidthContainsEveryControlInTheExpectedRow()",
            "func testPreferredHeightCallbackReportsModeTransition()",
            "func testLockButtonRequestsOneCentrallyGuardedToggle()",
            'XCTAssertFalse(view.isHidden, "\\(identifier) should be visible")',
            "let expectedAccessibilityRoles:",
        ),
    )
    require_source_markers(
        SHORTCUT_TESTS_PATH,
        (
            "func testLockModeRequiresAnExactRegisteredRecoveryChord()",
            "LockModeRecoveryPolicy.canToggle(",
            "LockModeRecoveryPolicy.requiresForcedUnlock(",
        ),
    )
    require_source_markers(
        INTEGRATION_TESTS_PATH,
        (
            "UITestConfig.configure(app)",
            "func testVideoAndControlsAreOneCanonicalManagedWindow()",
            'app.windows["window-controls"].exists',
            "func testLockButtonLocksAndLocalKeyboardUnlocksOverlay()",
        ),
    )

    production_sources = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(PRODUCTION_SWIFT_ROOT.rglob("*.swift"))
    )
    prohibited_split_window_markers = (
        "controlWindow",
        '"window-controls"',
        "createControlWindow",
    )
    for marker in prohibited_split_window_markers:
        if marker in production_sources:
            fail(
                "production Swift retains separately managed control-window "
                f"architecture marker: {marker}"
            )
    split_window_pattern = re.compile(
        r"\b(?:control|controls|controlBar|toolbar)Window\b|"
        r"addChildWindow\s*\(\s*(?:control|controls|controlBar|toolbar)"
    )
    split_window_match = split_window_pattern.search(production_sources)
    if split_window_match is not None:
        fail(
            "production Swift retains separately managed control-window "
            f"architecture: {split_window_match.group(0)}"
        )

    # Keep these reads live so a future refactor cannot satisfy the gate by
    # moving only comments into the expected files.
    if "ControlBar(" not in main_view:
        fail("the canonical main view does not construct its integral control bar")
    if (
        "OverlayWindowPolicy" not in app_delegate
        or "OverlayWindowPolicy" not in window_policy
    ):
        fail("the primary window is not governed by OverlayWindowPolicy")

    policy_pipeline = re.search(
        r"Publishers\.CombineLatest\(\s*"
        r"videoState\.\$isLocked,\s*"
        r"videoState\.\$isAlwaysOnTop\s*"
        r"\).*?\.store\(in:\s*&cancellables\)",
        app_delegate,
        re.DOTALL,
    )
    if policy_pipeline is None:
        fail("the atomic overlay policy publisher pipeline is missing")
    if ".receive(on:" in policy_pipeline.group(0):
        fail(
            "lock and unlock policy application must be synchronous; "
            "a queued receive(on:) leaves a window-manager race"
        )
    if "precondition(Thread.isMainThread)" not in policy_pipeline.group(0):
        fail("the synchronous overlay policy pipeline must require the AppKit main thread")


def validate_documentation_implementation(contract: dict[str, object]) -> None:
    validate_exact_value(
        contract.get("documentation"),
        EXPECTED_DOCUMENTATION_CONTRACT,
        "documentation",
    )

    require_source_markers(
        APP_DELEGATE_PATH,
        (
            "DocumentationView(rootURL: helpRootURL)",
            'window.setAccessibilityIdentifier("window-documentation")',
        ),
    )
    require_source_markers(
        DOCUMENTATION_VIEW_PATH,
        (
            "final class DocumentationTextView: NSTextView",
            ".documentType: NSAttributedString.DocumentType.html",
            "guard requestedURL.isFileURL else { return nil }",
            'pageURL.pathExtension.lowercased() == "html"',
            "pageURL.path.hasPrefix(rootPath)",
            'textView.setAccessibilityIdentifier("documentation-page")',
            "textView.textStorage?.setAttributedString(page.attributedText)",
            "textView.setAccessibilityValue(page.attributedText.string)",
        ),
    )

    prohibited_webkit_pattern = re.compile(
        r"(?m)^\s*import\s+WebKit\b|"
        r"\bWKWebView\b|"
        r"\bWKURLSchemeHandler\b|"
        r"\bWKNavigation[A-Za-z]*\b"
    )
    for path in sorted(PRODUCTION_SWIFT_ROOT.rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        match = prohibited_webkit_pattern.search(source)
        if match is not None:
            fail(
                f"{path.relative_to(ROOT)} uses prohibited WebKit "
                f"documentation implementation marker: {match.group(0).strip()}"
            )

    if not HELP_HOME_PATH.is_file():
        fail(f"Help home page is missing: {HELP_HOME_PATH.relative_to(ROOT)}")
    home_prose = normalized_prose(HELP_HOME_PATH.read_text(encoding="utf-8"))
    for marker in ("reframer help", "product boundaries"):
        if marker not in home_prose:
            fail(
                f"{HELP_HOME_PATH.relative_to(ROOT)} omits required rendered "
                f"content marker: {marker}"
            )


def validate_public_claim_markers() -> None:
    for path, markers in PUBLIC_CLAIM_MARKERS.items():
        if not path.is_file():
            fail(f"required public document is missing: {path.relative_to(ROOT)}")
        prose = normalized_prose(path.read_text(encoding="utf-8"))
        for marker in markers:
            if marker not in prose:
                fail(
                    f"{path.relative_to(ROOT)} omits build-3 public claim: "
                    f"{marker}"
                )


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
        "lockEntryRequirement": (
            "The exact configured global Lock/Unlock chord must be registered "
            "before whole-overlay click-through can begin"
        ),
        "lockEntryFailure": (
            "Lock is refused and recovery guidance identifies the configured chord"
        ),
        "lockRecoveryLoss": (
            "Registration loss, conflict, recording suspension, or disabling "
            "global shortcuts while locked immediately unlocks the overlay "
            "and reports recovery"
        ),
        "unlockAvailability": "Unlocking is always permitted",
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
    if type(contract) is not dict:
        fail("product contract root must be an object")
    if set(contract) != EXPECTED_CONTRACT_KEYS:
        fail(
            f"product contract keys {sorted(contract)} do not equal "
            f"{sorted(EXPECTED_CONTRACT_KEYS)}"
        )
    validate_exact_value(contract.get("schemaVersion"), 2, "schemaVersion")
    validate_overlay_implementation(contract)
    validate_documentation_implementation(contract)

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
    if privacy.get("networkAccess") is not False:
        fail("product contract must prohibit network access")

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
    validate_public_claim_markers()

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
