import AppKit
import Carbon
import XCTest
@testable import Reframer

final class ShortcutSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "Reframer.ShortcutSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testProductContractFrameDefaultsUsePageDownForForward() {
        let settings = ShortcutSettings(userDefaults: defaults)

        XCTAssertEqual(
            settings.binding(for: .frameStepForward).shortcut?.keyCode,
            KeyCode.pageDown
        )
        XCTAssertEqual(
            settings.binding(for: .frameStepBackward).shortcut?.keyCode,
            KeyCode.pageUp
        )
        XCTAssertEqual(settings.displayString(for: .frameStepForward), "⌘PgDn")
        XCTAssertEqual(settings.displayString(for: .frameStepBackward), "⌘PgUp")
    }

    func testResolverProducesOneTenAndHundredVariants() {
        let settings = ShortcutSettings(userDefaults: defaults)
        let command = NSEvent.ModifierFlags.command.rawValue
        let shift = NSEvent.ModifierFlags.shift.rawValue
        let commandShift = NSEvent.ModifierFlags([.command, .shift]).rawValue

        let forward = settings.resolve(
            stroke: ShortcutKeystroke(keyCode: KeyCode.pageDown, modifiers: command),
            scope: .local
        )
        XCTAssertEqual(forward, ShortcutMatch(action: .frameStepForward, variant: .primary))
        XCTAssertEqual(settings.command(for: forward!), .step(.forward, amount: 1))

        let forwardTen = settings.resolve(
            stroke: ShortcutKeystroke(keyCode: KeyCode.pageDown, modifiers: commandShift),
            scope: .local
        )
        XCTAssertEqual(
            forwardTen,
            ShortcutMatch(action: .frameStepForward, variant: .multiplied(10))
        )
        XCTAssertEqual(settings.command(for: forwardTen!), .step(.forward, amount: 10))

        let panTen = settings.resolve(
            stroke: ShortcutKeystroke(keyCode: KeyCode.leftArrow, modifiers: shift),
            scope: .local
        )
        XCTAssertEqual(panTen, ShortcutMatch(action: .panLeft, variant: .multiplied(10)))

        let panHundred = settings.resolve(
            stroke: ShortcutKeystroke(keyCode: KeyCode.leftArrow, modifiers: commandShift),
            scope: .local
        )
        XCTAssertEqual(
            panHundred,
            ShortcutMatch(action: .panLeft, variant: .multiplied(100))
        )
        XCTAssertEqual(settings.command(for: panHundred!), .pan(x: -100, y: 0))
    }

    func testScopeAndRepeatPolicySuppressIneligibleCommands() {
        let settings = ShortcutSettings(userDefaults: defaults)

        XCTAssertNil(settings.resolve(
            stroke: ShortcutKeystroke(keyCode: KeyCode.leftArrow, modifiers: 0),
            scope: .global
        ))
        XCTAssertNotNil(settings.resolve(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.pageDown,
                modifiers: NSEvent.ModifierFlags.command.rawValue,
                isRepeat: true
            ),
            scope: .global
        ))
        XCTAssertNil(settings.resolve(
            stroke: ShortcutKeystroke(keyCode: KeyCode.l, modifiers: 0, isRepeat: true),
            scope: .local
        ))
        XCTAssertNil(settings.resolve(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.l,
                modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue,
                isRepeat: true
            ),
            scope: .global
        ))
    }

    func testRepeatedNonRepeatingShortcutIsConsumedBeforeMenuFallback() {
        let settings = ShortcutSettings(userDefaults: defaults)

        XCTAssertEqual(
            settings.eventResolution(
                stroke: ShortcutKeystroke(
                    keyCode: KeyCode.space,
                    modifiers: 0,
                    isRepeat: true
                ),
                scope: .local
            ),
            .consumeWithoutDispatch(
                ShortcutMatch(action: .playPause, variant: .primary)
            )
        )
        XCTAssertEqual(
            settings.eventResolution(
                stroke: ShortcutKeystroke(
                    keyCode: KeyCode.l,
                    modifiers: 0,
                    isRepeat: true
                ),
                scope: .local
            ),
            .consumeWithoutDispatch(
                ShortcutMatch(action: .toggleLock, variant: .primary)
            )
        )
    }

    func testCommandQuestionMarkRoutesToDocumentationBeforeHelpMenuSearch() {
        let modifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue
        let stroke = ShortcutKeystroke(
            keyCode: KeyCode.questionMark,
            modifiers: modifiers
        )

        XCTAssertEqual(
            FixedCommandShortcutRouting.eventResolution(stroke: stroke),
            .dispatch(.openDocumentation)
        )
        XCTAssertEqual(
            FixedCommandShortcutRouting.eventResolution(stroke: ShortcutKeystroke(
                keyCode: KeyCode.questionMark,
                modifiers: modifiers,
                isRepeat: true
            )),
            .consumeWithoutDispatch
        )
        XCTAssertEqual(
            FixedCommandShortcutRouting.eventResolution(stroke: ShortcutKeystroke(
                keyCode: KeyCode.questionMark,
                modifiers: NSEvent.ModifierFlags.command.rawValue
            )),
            .unmatched
        )
    }

    func testFocusedEditorReceivesRecognizedNonRepeatingAutorepeat() {
        let settings = ShortcutSettings(userDefaults: defaults)
        let stroke = ShortcutKeystroke(
            keyCode: KeyCode.h,
            modifiers: 0,
            isRepeat: true
        )
        let resolution = settings.eventResolution(
            stroke: stroke,
            scope: .local
        )

        XCTAssertEqual(
            resolution,
            .consumeWithoutDispatch(
                ShortcutMatch(action: .showHelp, variant: .primary)
            )
        )
        XCTAssertTrue(
            ShortcutControlRouting.focusedControlOwns(
                stroke: stroke,
                kind: .textEditor
            )
        )
        XCTAssertEqual(
            FocusedShortcutEventRouting.decision(
                resolution: resolution,
                focusedResponderOwnsStroke: true
            ),
            .deliverToFocusedResponder
        )
        XCTAssertEqual(
            FocusedShortcutEventRouting.decision(
                resolution: resolution,
                focusedResponderOwnsStroke: false
            ),
            .consumeWithoutDispatch
        )
    }

    func testRepeatedEligibleShortcutStillDispatches() {
        let settings = ShortcutSettings(userDefaults: defaults)
        let command = NSEvent.ModifierFlags.command.rawValue

        XCTAssertEqual(
            settings.eventResolution(
                stroke: ShortcutKeystroke(
                    keyCode: KeyCode.pageDown,
                    modifiers: command,
                    isRepeat: true
                ),
                scope: .local
            ),
            .dispatch(
                ShortcutMatch(
                    action: .frameStepForward,
                    variant: .primary
                )
            )
        )
        XCTAssertEqual(
            settings.eventResolution(
                stroke: ShortcutKeystroke(
                    keyCode: KeyCode.leftArrow,
                    modifiers: 0,
                    isRepeat: true
                ),
                scope: .local
            ),
            .dispatch(
                ShortcutMatch(
                    action: .panLeft,
                    variant: .primary
                )
            )
        )
    }

    func testValidationRejectsDuplicatesReservedAndUnsafeGlobalKeys() {
        let settings = ShortcutSettings(userDefaults: defaults)

        assertFailure(
            .duplicate(.resetZoom),
            from: settings.setShortcut(
                ShortcutSettings.Shortcut(keyCode: KeyCode.zero, modifiers: 0),
                for: .resetView
            )
        )
        assertFailure(
            .reservedSystemShortcut,
            from: settings.setShortcut(
                ShortcutSettings.Shortcut(
                    keyCode: KeyCode.o,
                    modifiers: NSEvent.ModifierFlags.command.rawValue
                ),
                for: .resetView
            )
        )
        assertFailure(
            .unsafeGlobalShortcut,
            from: settings.setShortcut(
                ShortcutSettings.Shortcut(keyCode: KeyCode.l, modifiers: 0),
                for: .globalToggleLock
            )
        )
        assertFailure(
            .unsafeGlobalShortcut,
            from: settings.setShortcut(
                ShortcutSettings.Shortcut(
                    keyCode: KeyCode.l,
                    modifiers: NSEvent.ModifierFlags.option.rawValue
                ),
                for: .globalToggleLock
            )
        )
    }

    func testValidationRejectsMultiplierCollapse() {
        let settings = ShortcutSettings(userDefaults: defaults)
        let shortcut = ShortcutSettings.Shortcut(
            keyCode: KeyCode.leftArrow,
            modifiers: NSEvent.ModifierFlags.shift.rawValue,
            multiplierModifier: NSEvent.ModifierFlags.shift.rawValue
        )

        assertFailure(
            .modifierCollapse,
            from: settings.setShortcut(shortcut, for: .panLeft)
        )
    }

    func testClearDisableAndReenablePersist() {
        let settings = ShortcutSettings(userDefaults: defaults)
        assertSuccess(settings.setEnabled(false, for: .panLeft))
        settings.clearShortcut(for: .panRight)

        let restored = ShortcutSettings(userDefaults: defaults)
        XCTAssertFalse(restored.binding(for: .panLeft).isEnabled)
        XCTAssertNotNil(restored.binding(for: .panLeft).shortcut)
        XCTAssertTrue(restored.binding(for: .panRight).isEnabled)
        XCTAssertNil(restored.binding(for: .panRight).shortcut)
        XCTAssertEqual(restored.displayString(for: .panLeft), "Disabled")
        XCTAssertEqual(restored.displayString(for: .panRight), "Not set")

        assertSuccess(restored.setEnabled(true, for: .panLeft))
        XCTAssertTrue(ShortcutSettings(userDefaults: defaults).binding(for: .panLeft).isEnabled)
    }

    func testGlobalShortcutPreferencePersistsAndStopsGlobalResolution() {
        let settings = ShortcutSettings(userDefaults: defaults)
        settings.setGlobalShortcutsEnabled(false)

        let restored = ShortcutSettings(userDefaults: defaults)
        XCTAssertFalse(restored.globalShortcutsEnabled)
        XCTAssertNil(restored.resolve(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.pageDown,
                modifiers: NSEvent.ModifierFlags.command.rawValue
            ),
            scope: .global
        ))
        XCTAssertNotNil(restored.resolve(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.pageDown,
                modifiers: NSEvent.ModifierFlags.command.rawValue
            ),
            scope: .local
        ))
    }

    func testInvalidRestoredCustomBindingIsPreservedButDisabled() throws {
        let object: [String: Any] = [
            "schemaVersion": 3,
            "globalShortcutsEnabled": true,
            "bindings": [
                ShortcutSettings.Action.resetView.rawValue: [
                    "isEnabled": true,
                    "shortcut": [
                        "keyCode": KeyCode.o,
                        "modifiers": NSEvent.ModifierFlags.command.rawValue,
                        "multiplierModifier": NSEvent.ModifierFlags.shift.rawValue
                    ]
                ]
            ]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: object),
            forKey: ShortcutSettings.persistenceKey
        )

        let restored = ShortcutSettings(userDefaults: defaults)
        let binding = restored.binding(for: .resetView)
        XCTAssertFalse(binding.isEnabled)
        XCTAssertEqual(binding.shortcut?.keyCode, KeyCode.o)
        XCTAssertEqual(
            binding.shortcut?.modifiers,
            NSEvent.ModifierFlags.command.rawValue
        )
    }

    func testLegacyUntouchedFramePairMigratesToCorrectDirections() {
        defaults.set([
            ShortcutSettings.Action.frameStepForward.rawValue: [
                "keyCode": NSNumber(value: KeyCode.pageUp),
                "modifiers": NSNumber(value: NSEvent.ModifierFlags.command.rawValue)
            ],
            ShortcutSettings.Action.frameStepBackward.rawValue: [
                "keyCode": NSNumber(value: KeyCode.pageDown),
                "modifiers": NSNumber(value: NSEvent.ModifierFlags.command.rawValue)
            ]
        ], forKey: ShortcutSettings.legacyPersistenceKey)

        let settings = ShortcutSettings(userDefaults: defaults)

        XCTAssertEqual(
            settings.binding(for: .frameStepForward).shortcut?.keyCode,
            KeyCode.pageDown
        )
        XCTAssertEqual(
            settings.binding(for: .frameStepBackward).shortcut?.keyCode,
            KeyCode.pageUp
        )
        XCTAssertNotNil(defaults.data(forKey: ShortcutSettings.persistenceKey))
    }

    func testLegacyCustomizedPairIsPreserved() {
        defaults.set([
            ShortcutSettings.Action.frameStepForward.rawValue: [
                "keyCode": NSNumber(value: 122),
                "modifiers": NSNumber(value: NSEvent.ModifierFlags.command.rawValue)
            ],
            ShortcutSettings.Action.frameStepBackward.rawValue: [
                "keyCode": NSNumber(value: 120),
                "modifiers": NSNumber(value: NSEvent.ModifierFlags.command.rawValue)
            ]
        ], forKey: ShortcutSettings.legacyPersistenceKey)

        let settings = ShortcutSettings(userDefaults: defaults)

        XCTAssertEqual(settings.binding(for: .frameStepForward).shortcut?.keyCode, 122)
        XCTAssertEqual(settings.binding(for: .frameStepBackward).shortcut?.keyCode, 120)
    }

    func testRecordingEscapeCancelsAndDeleteClears() {
        let settings = ShortcutSettings(userDefaults: defaults)
        settings.beginRecording(for: .panLeft)
        XCTAssertEqual(
            settings.record(stroke: ShortcutKeystroke(keyCode: KeyCode.escape, modifiers: 0)),
            .consumed
        )
        XCTAssertNil(settings.recordingAction)
        XCTAssertNotNil(settings.binding(for: .panLeft).shortcut)

        settings.beginRecording(for: .panLeft)
        XCTAssertEqual(
            settings.record(stroke: ShortcutKeystroke(keyCode: KeyCode.delete, modifiers: 0)),
            .consumed
        )
        XCTAssertNil(settings.binding(for: .panLeft).shortcut)
    }

    func testRecordingPersistsLayoutCharacterForDisplayAndMenu() {
        let settings = ShortcutSettings(userDefaults: defaults)
        settings.beginRecording(for: .playPause)

        XCTAssertEqual(
            settings.record(
                stroke: ShortcutKeystroke(
                    keyCode: 0,
                    modifiers: 0,
                    charactersIgnoringModifiers: "q"
                )
            ),
            .saved
        )
        XCTAssertEqual(settings.displayString(for: .playPause), "Q")
        XCTAssertEqual(
            settings.binding(for: .playPause).shortcut?.menuKeyEquivalent,
            "q"
        )

        let restored = ShortcutSettings(userDefaults: defaults)
        XCTAssertEqual(restored.displayString(for: .playPause), "Q")
        XCTAssertEqual(
            restored.binding(for: .playPause).shortcut?.menuKeyEquivalent,
            "q"
        )
    }

    func testRecordingPreservesShiftedCharactersForMenuDispatch() {
        let settings = ShortcutSettings(userDefaults: defaults)
        let shift = NSEvent.ModifierFlags.shift.rawValue
        settings.beginRecording(for: .playPause)

        XCTAssertEqual(
            settings.record(
                stroke: ShortcutKeystroke(
                    keyCode: 18,
                    modifiers: shift,
                    charactersIgnoringModifiers: "!"
                )
            ),
            .saved
        )
        XCTAssertEqual(settings.displayString(for: .playPause), "⇧!")
        XCTAssertEqual(
            settings.binding(for: .playPause).shortcut?.menuKeyEquivalent,
            "!"
        )

        settings.beginRecording(for: .playPause)
        XCTAssertEqual(
            settings.record(
                stroke: ShortcutKeystroke(
                    keyCode: 12,
                    modifiers: shift,
                    charactersIgnoringModifiers: "Q"
                )
            ),
            .saved
        )
        XCTAssertEqual(settings.displayString(for: .playPause), "⇧Q")
        XCTAssertEqual(
            settings.binding(for: .playPause).shortcut?.menuKeyEquivalent,
            "Q"
        )
    }

    func testRecordingLiteralSpaceUsesCanonicalSpaceKey() {
        let settings = ShortcutSettings(userDefaults: defaults)
        settings.beginRecording(for: .playPause)

        XCTAssertEqual(
            settings.record(
                stroke: ShortcutKeystroke(
                    keyCode: KeyCode.space,
                    modifiers: 0,
                    charactersIgnoringModifiers: " "
                )
            ),
            .saved
        )
        let shortcut = settings.binding(for: .playPause).shortcut
        XCTAssertNil(shortcut?.recordedCharacter)
        XCTAssertEqual(settings.displayString(for: .playPause), "Space")
        XCTAssertEqual(shortcut?.menuKeyEquivalent, " ")
    }

    func testTabCannotOverrideKeyboardFocusTraversal() {
        let settings = ShortcutSettings(userDefaults: defaults)
        settings.beginRecording(for: .playPause)

        XCTAssertEqual(
            settings.record(
                stroke: ShortcutKeystroke(
                    keyCode: KeyCode.tab,
                    modifiers: 0,
                    charactersIgnoringModifiers: "\t"
                )
            ),
            .focusTraversal
        )
        XCTAssertNil(settings.recordingAction)

        assertFailure(
            .unsupportedKey,
            from: settings.setShortcut(
                ShortcutSettings.Shortcut(
                    keyCode: KeyCode.tab,
                    modifiers: NSEvent.ModifierFlags.shift.rawValue
                ),
                for: .playPause
            )
        )
    }

    @MainActor
    func testShortcutSettingsWindowContractIsResizable() {
        XCTAssertTrue(
            ShortcutSettingsWindowConfiguration.styleMask.contains(.resizable)
        )
        XCTAssertTrue(
            ShortcutSettingsWindowConfiguration.styleMask.contains(.borderless)
        )
        XCTAssertEqual(HelpView.minimumWindowSize, NSSize(width: 700, height: 520))
        XCTAssertEqual(HelpView.preferredWindowSize, NSSize(width: 780, height: 1_020))
        XCTAssertGreaterThan(
            HelpView.preferredWindowSize.height,
            HelpView.minimumWindowSize.height
        )
    }

    @MainActor
    func testShortcutSettingsUsesAlignedSharedColumns() {
        let hosted = makeHostedShortcutSettingsView(
            size: HelpView.preferredWindowSize
        )
        let view = hosted.view

        let actions = ShortcutSettings.Action.allCases
        let keyOrigins = actions.compactMap {
            descendant(withIdentifier: "shortcut-key-\($0.rawValue)", in: view)
                .map { $0.convert($0.bounds, to: view).minX }
        }
        let actionOrigins = actions.compactMap {
            descendant(withIdentifier: "shortcut-action-\($0.rawValue)", in: view)
                .map { $0.convert($0.bounds, to: view).minX }
        }
        let clearOrigins = actions.compactMap {
            descendant(withIdentifier: "shortcut-clear-\($0.rawValue)", in: view)
                .map { $0.convert($0.bounds, to: view).minX }
        }
        let multiplierOrigins = actions
            .filter(\.hasMultiplierVariant)
            .compactMap {
                descendant(
                    withIdentifier: "shortcut-multiplier-\($0.rawValue)",
                    in: view
                ).map { $0.convert($0.bounds, to: view).minX }
            }

        XCTAssertEqual(keyOrigins.count, actions.count)
        XCTAssertEqual(actionOrigins.count, actions.count)
        XCTAssertEqual(clearOrigins.count, actions.count)
        assertAligned(keyOrigins)
        assertAligned(actionOrigins)
        assertAligned(clearOrigins)
        assertAligned(multiplierOrigins)

        let configurableKey = try! XCTUnwrap(
            descendant(withIdentifier: "shortcut-key-playPause", in: view)
        )
        let staticKey = try! XCTUnwrap(
            descendant(withIdentifier: "shortcut-key-static-drag-video", in: view)
        )
        let configurableAction = try! XCTUnwrap(
            descendant(withIdentifier: "shortcut-action-playPause", in: view)
        )
        let staticAction = try! XCTUnwrap(
            descendant(
                withIdentifier: "shortcut-action-static-drag-video",
                in: view
            )
        )
        XCTAssertEqual(
            configurableKey.convert(configurableKey.bounds, to: view).minX,
            staticKey.convert(staticKey.bounds, to: view).minX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            configurableAction.convert(configurableAction.bounds, to: view).minX,
            staticAction.convert(staticAction.bounds, to: view).minX,
            accuracy: 0.5
        )
    }

    @MainActor
    func testShortcutSettingsExpandedHeightShowsAllRowsAndMinimumHeightScrolls() {
        let expanded = makeHostedShortcutSettingsView(
            size: HelpView.preferredWindowSize
        )
        let expandedScroll = try! XCTUnwrap(
            descendant(withIdentifier: "shortcut-scroll", in: expanded.view)
                as? NSScrollView
        )
        XCTAssertLessThanOrEqual(
            expandedScroll.documentView?.frame.height ?? .greatestFiniteMagnitude,
            expandedScroll.contentView.bounds.height + 1
        )
        XCTAssertLessThanOrEqual(
            expandedScroll.documentView?.frame.width ?? .greatestFiniteMagnitude,
            expandedScroll.contentView.bounds.width + 1
        )

        let compact = makeHostedShortcutSettingsView(
            size: HelpView.minimumWindowSize
        )
        let compactScroll = try! XCTUnwrap(
            descendant(withIdentifier: "shortcut-scroll", in: compact.view)
                as? NSScrollView
        )
        XCTAssertGreaterThan(
            compactScroll.documentView?.frame.height ?? 0,
            compactScroll.contentView.bounds.height + 1
        )
        XCTAssertLessThanOrEqual(
            compactScroll.documentView?.frame.width ?? .greatestFiniteMagnitude,
            compactScroll.contentView.bounds.width + 1
        )
    }

    @MainActor
    func testShortcutSettingsGlobalScopeAppearsOnceAndFocusOrderIsRowMajor() {
        let hosted = makeHostedShortcutSettingsView(
            size: HelpView.preferredWindowSize
        )
        let view = hosted.view
        let globalLockLabel = try! XCTUnwrap(
            descendant(
                withIdentifier: "shortcut-action-globalToggleLock",
                in: view
            ) as? NSTextField
        )
        XCTAssertEqual(globalLockLabel.stringValue, "Toggle lock · Global")

        let close = try! XCTUnwrap(
            descendant(withIdentifier: "help-close", in: view)
        )
        let firstEnable = try! XCTUnwrap(
            descendant(withIdentifier: "shortcut-enable-playPause", in: view)
        )
        let firstKey = try! XCTUnwrap(
            descendant(withIdentifier: "shortcut-key-playPause", in: view)
        )
        let firstClear = try! XCTUnwrap(
            descendant(withIdentifier: "shortcut-clear-playPause", in: view)
        )
        let secondEnable = try! XCTUnwrap(
            descendant(
                withIdentifier: "shortcut-enable-frameStepForward",
                in: view
            )
        )
        XCTAssertTrue(close.nextKeyView === firstEnable)
        XCTAssertTrue(firstEnable.nextKeyView === firstKey)
        XCTAssertTrue(firstKey.nextKeyView === firstClear)
        XCTAssertTrue(firstClear.nextKeyView === secondEnable)
    }

    func testAcceptedFunctionAndNavigationKeysHaveMenuEquivalents() {
        let acceptedSpecialKeys: [UInt16] = [
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
            KeyCode.home,
            KeyCode.end,
            KeyCode.pageUp,
            KeyCode.pageDown,
            KeyCode.leftArrow,
            KeyCode.rightArrow,
            KeyCode.upArrow,
            KeyCode.downArrow,
            KeyCode.delete,
            KeyCode.forwardDelete
        ]

        for keyCode in acceptedSpecialKeys {
            XCTAssertNotNil(
                ShortcutSettings.menuKeyEquivalent(for: keyCode),
                "Expected a menu equivalent for accepted key code \(keyCode)"
            )
        }
    }

    func testAuxiliaryPanelRoutingPrefersKeyThenFrontmostVisiblePanel() {
        let allPanels: Set<AuxiliaryPanelKind> = [
            .shortcutSettings,
            .filters,
            .documentation
        ]

        XCTAssertEqual(
            AuxiliaryPanelRouting.target(
                keyPanel: .filters,
                orderedVisiblePanels: [.documentation, .shortcutSettings, .filters],
                visiblePanels: allPanels
            ),
            .filters
        )
        XCTAssertEqual(
            AuxiliaryPanelRouting.target(
                keyPanel: nil,
                orderedVisiblePanels: [.documentation, .shortcutSettings],
                visiblePanels: [.documentation, .shortcutSettings]
            ),
            .documentation
        )
        XCTAssertNil(
            AuxiliaryPanelRouting.target(
                keyPanel: nil,
                orderedVisiblePanels: [],
                visiblePanels: []
            )
        )
    }

    func testGlobalHotKeyPlanRegistersOnlyEnabledGlobalVariants() {
        let settings = ShortcutSettings(userDefaults: defaults)

        let descriptors = GlobalHotKeyPlan.descriptors(for: settings)

        XCTAssertEqual(descriptors.count, 5)
        XCTAssertEqual(
            descriptors.map(\.match),
            [
                ShortcutMatch(action: .frameStepForward, variant: .primary),
                ShortcutMatch(action: .frameStepForward, variant: .multiplied(10)),
                ShortcutMatch(action: .frameStepBackward, variant: .primary),
                ShortcutMatch(action: .frameStepBackward, variant: .multiplied(10)),
                ShortcutMatch(action: .globalToggleLock, variant: .primary)
            ]
        )
        XCTAssertEqual(descriptors.map(\.identifier), [1, 2, 3, 4, 5])
        XCTAssertEqual(descriptors.filter(\.allowsRepeat).count, 4)
        XCTAssertFalse(descriptors.last!.allowsRepeat)

        let lockOnlyDescriptors = GlobalHotKeyPlan.descriptors(
            for: settings,
            includeFrameSteps: false
        )
        XCTAssertEqual(lockOnlyDescriptors.map(\.identifier), [5])

        assertSuccess(settings.setEnabled(false, for: .frameStepBackward))
        let reducedDescriptors = GlobalHotKeyPlan.descriptors(for: settings)
        XCTAssertEqual(reducedDescriptors.count, 3)
        XCTAssertEqual(reducedDescriptors.map(\.identifier), [1, 2, 5])

        settings.setGlobalShortcutsEnabled(false)
        XCTAssertTrue(GlobalHotKeyPlan.descriptors(for: settings).isEmpty)
    }

    func testGlobalHotKeyPlanMapsAppKitModifiersToCarbon() {
        let commandShiftOptionControl = NSEvent.ModifierFlags([
            .command, .shift, .option, .control
        ]).rawValue

        XCTAssertEqual(
            GlobalHotKeyPlan.carbonModifiers(from: commandShiftOptionControl),
            UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        XCTAssertEqual(GlobalHotKeyPlan.carbonModifiers(from: 0), 0)

        let settings = ShortcutSettings(userDefaults: defaults)
        let forward = GlobalHotKeyPlan.descriptors(for: settings).first {
            $0.match == ShortcutMatch(action: .frameStepForward, variant: .primary)
        }
        let forwardTen = GlobalHotKeyPlan.descriptors(for: settings).first {
            $0.match == ShortcutMatch(
                action: .frameStepForward,
                variant: .multiplied(10)
            )
        }
        XCTAssertEqual(forward?.carbonModifiers, UInt32(cmdKey))
        XCTAssertEqual(forwardTen?.carbonModifiers, UInt32(cmdKey | shiftKey))
    }

    func testHeldNonRepeatingGlobalHotKeySurvivesEquivalentReconfiguration() {
        let settings = ShortcutSettings(userDefaults: defaults)
        let previousDescriptors = Dictionary(
            uniqueKeysWithValues: GlobalHotKeyPlan.descriptors(for: settings)
                .map { ($0.identifier, $0) }
        )
        let currentDescriptors = Dictionary(
            uniqueKeysWithValues: GlobalHotKeyPlan.descriptors(
                for: settings,
                includeFrameSteps: false
            ).map { ($0.identifier, $0) }
        )
        let lockIdentifier: UInt32 = 5
        let changes = GlobalHotKeyRegistrationChanges.between(
            current: previousDescriptors,
            desired: currentDescriptors
        )
        var state = GlobalHotKeyPressState()

        XCTAssertEqual(changes.retainedIdentifiers, [lockIdentifier])
        XCTAssertEqual(changes.removedIdentifiers, [1, 2, 3, 4])
        XCTAssertTrue(changes.addedIdentifiers.isEmpty)
        XCTAssertTrue(
            state.shouldDeliverPress(
                identifier: lockIdentifier,
                allowsRepeat: false
            )
        )
        XCTAssertEqual(
            state.pressedNonRepeatingIdentifiers,
            [lockIdentifier]
        )
        XCTAssertFalse(
            state.shouldDeliverPress(
                identifier: lockIdentifier,
                allowsRepeat: false
            ),
            "Re-registering after the lock transition must not turn a held key into a new press"
        )

        state.release(identifier: lockIdentifier)
        XCTAssertTrue(state.pressedNonRepeatingIdentifiers.isEmpty)
        XCTAssertTrue(
            state.shouldDeliverPress(
                identifier: lockIdentifier,
                allowsRepeat: false
            ),
            "A physical release must allow the next lock press"
        )
    }

    func testChangedOrRemovedGlobalHotKeyIsReplacedAndClearsHeldState() {
        let settings = ShortcutSettings(userDefaults: defaults)
        let descriptors = Dictionary(
            uniqueKeysWithValues: GlobalHotKeyPlan.descriptors(for: settings)
                .map { ($0.identifier, $0) }
        )
        let lockIdentifier: UInt32 = 5
        let lockDescriptor = try! XCTUnwrap(descriptors[lockIdentifier])
        let changedLockDescriptor = GlobalHotKeyDescriptor(
            identifier: lockDescriptor.identifier,
            match: lockDescriptor.match,
            keyCode: lockDescriptor.keyCode,
            carbonModifiers: lockDescriptor.carbonModifiers | UInt32(optionKey),
            displayString: "⌘⇧⌥L",
            allowsRepeat: lockDescriptor.allowsRepeat
        )
        let replacement = [lockIdentifier: changedLockDescriptor]
        let changes = GlobalHotKeyRegistrationChanges.between(
            current: descriptors,
            desired: replacement
        )
        var state = GlobalHotKeyPressState()

        XCTAssertTrue(changes.retainedIdentifiers.isEmpty)
        XCTAssertEqual(changes.removedIdentifiers, [1, 2, 3, 4, 5])
        XCTAssertEqual(changes.addedIdentifiers, [lockIdentifier])
        XCTAssertTrue(
            state.shouldDeliverPress(
                identifier: lockIdentifier,
                allowsRepeat: false
            )
        )
        for identifier in changes.removedIdentifiers {
            state.release(identifier: identifier)
        }
        XCTAssertTrue(
            state.pressedNonRepeatingIdentifiers.isEmpty,
            "Replacing a registration must not carry held state to the new chord"
        )

        XCTAssertTrue(
            state.shouldDeliverPress(
                identifier: lockIdentifier,
                allowsRepeat: false
            )
        )
        state.reset()
        XCTAssertTrue(
            state.pressedNonRepeatingIdentifiers.isEmpty,
            "Disabling, suspending, or invalidating registrations must clear held state"
        )
    }

    func testGlobalRegistrationStatusExposesConflictRecovery() {
        let failure = GlobalShortcutRegistrationFailure(
            action: .globalToggleLock,
            variant: .primary,
            shortcut: "⌘⇧L",
            statusCode: Int32(eventHotKeyExistsErr)
        )
        let status = GlobalShortcutRegistrationStatus.partial(
            registered: 4,
            failures: [failure]
        )

        XCTAssertTrue(status.hasFailures)
        XCTAssertTrue(failure.recoveryDescription.contains("another app"))

        let settings = ShortcutSettings(userDefaults: defaults)
        settings.setGlobalRegistrationStatus(status)
        XCTAssertEqual(settings.globalRegistrationStatus, status)
        settings.setGlobalShortcutsEnabled(false)
        XCTAssertEqual(settings.globalRegistrationStatus, .disabled)
    }

    func testLockModeRequiresAnExactRegisteredRecoveryChord() {
        XCTAssertTrue(LockModeRecoveryPolicy.canToggle(
            isCurrentlyLocked: false,
            isRecoveryRegistered: true
        ))
        XCTAssertFalse(LockModeRecoveryPolicy.canToggle(
            isCurrentlyLocked: false,
            isRecoveryRegistered: false
        ))
        XCTAssertTrue(
            LockModeRecoveryPolicy.canToggle(
                isCurrentlyLocked: true,
                isRecoveryRegistered: false
            ),
            "Unlocking must remain possible after an external registration loss"
        )
        XCTAssertTrue(LockModeRecoveryPolicy.requiresForcedUnlock(
            isCurrentlyLocked: true,
            isRecoveryRegistered: false
        ))
        XCTAssertFalse(LockModeRecoveryPolicy.requiresForcedUnlock(
            isCurrentlyLocked: true,
            isRecoveryRegistered: true
        ))
        XCTAssertFalse(LockModeRecoveryPolicy.requiresForcedUnlock(
            isCurrentlyLocked: false,
            isRecoveryRegistered: false
        ))
    }

    func testFocusedButtonsDoNotSwallowPlainOrShiftProductShortcuts() {
        for keyCode in [KeyCode.h, KeyCode.f, KeyCode.l, KeyCode.r, KeyCode.zero] {
            XCTAssertFalse(ShortcutControlRouting.focusedControlOwns(
                stroke: ShortcutKeystroke(keyCode: keyCode, modifiers: 0),
                kind: .button
            ))
            XCTAssertFalse(ShortcutControlRouting.focusedControlOwns(
                stroke: ShortcutKeystroke(
                    keyCode: keyCode,
                    modifiers: NSEvent.ModifierFlags.shift.rawValue
                ),
                kind: .button
            ))
        }

        XCTAssertTrue(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.space, modifiers: 0),
            kind: .button
        ))
        XCTAssertTrue(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.returnKey, modifiers: 0),
            kind: .button
        ))
    }

    func testFocusedSliderAndPopUpRetainOnlyNativeNavigationAndActivation() {
        XCTAssertTrue(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.leftArrow, modifiers: 0),
            kind: .slider
        ))
        XCTAssertFalse(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.h, modifiers: 0),
            kind: .slider
        ))
        XCTAssertFalse(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.leftArrow,
                modifiers: NSEvent.ModifierFlags.control.rawValue
            ),
            kind: .slider
        ))
        XCTAssertTrue(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.downArrow, modifiers: 0),
            kind: .popUpButton
        ))
        XCTAssertFalse(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.f, modifiers: 0),
            kind: .popUpButton
        ))
    }

    func testSystemSheetsBypassApplicationShortcutRouting() {
        XCTAssertTrue(
            ShortcutWindowRouting.shouldBypassApplicationShortcuts(
                isSystemSavePanel: true,
                hasSheetParent: false
            )
        )
        XCTAssertTrue(
            ShortcutWindowRouting.shouldBypassApplicationShortcuts(
                isSystemSavePanel: false,
                hasSheetParent: true
            )
        )
        XCTAssertFalse(
            ShortcutWindowRouting.shouldBypassApplicationShortcuts(
                isSystemSavePanel: false,
                hasSheetParent: false
            )
        )
    }

    func testTableAndDocumentationContentRetainNativeNavigation() {
        let nativeStrokes = [
            ShortcutKeystroke(keyCode: KeyCode.space, modifiers: 0),
            ShortcutKeystroke(keyCode: KeyCode.downArrow, modifiers: 0),
            ShortcutKeystroke(keyCode: KeyCode.pageDown, modifiers: 0)
        ]
        let table = NSTableView()
        let documentationContent = DocumentationTextView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240)
        )
        let embeddedDocumentationSubview = NSView(frame: documentationContent.bounds)
        documentationContent.addSubview(embeddedDocumentationSubview)

        for stroke in nativeStrokes {
            XCTAssertTrue(
                ShortcutControlRouting.focusedResponderOwns(
                    stroke: stroke,
                    responder: table
                )
            )
            XCTAssertTrue(
                ShortcutControlRouting.focusedResponderOwns(
                    stroke: stroke,
                    responder: embeddedDocumentationSubview
                )
            )
        }

        let commandPageDown = ShortcutKeystroke(
            keyCode: KeyCode.pageDown,
            modifiers: NSEvent.ModifierFlags.command.rawValue
        )
        XCTAssertFalse(
            ShortcutControlRouting.focusedResponderOwns(
                stroke: commandPageDown,
                responder: embeddedDocumentationSubview
            )
        )
        XCTAssertFalse(
            ShortcutControlRouting.focusedResponderOwns(
                stroke: ShortcutKeystroke(
                    keyCode: KeyCode.escape,
                    modifiers: 0
                ),
                responder: embeddedDocumentationSubview
            ),
            "Escape remains Reframer's advertised frontmost-context close command"
        )
    }

    func testTextEditorRetainsTextAndStandardEditingButNotAppCommands() {
        XCTAssertTrue(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.h, modifiers: 0),
            kind: .textEditor
        ))
        XCTAssertTrue(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.h,
                modifiers: NSEvent.ModifierFlags.shift.rawValue
            ),
            kind: .textEditor
        ))
        XCTAssertTrue(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.c,
                modifiers: NSEvent.ModifierFlags.command.rawValue
            ),
            kind: .textEditor
        ))
        XCTAssertFalse(ShortcutControlRouting.focusedControlOwns(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.o,
                modifiers: NSEvent.ModifierFlags.command.rawValue
            ),
            kind: .textEditor
        ))
    }

    func testRegisteredHotKeyUsesLocalGuardWhileActiveAndGlobalGuardWhileInactive() {
        let unlocked = ReframerCommandAvailabilityContext(
            isVideoLoaded: true,
            isLocked: false,
            canNavigateFrames: true,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false
        )
        let locked = ReframerCommandAvailabilityContext(
            isVideoLoaded: true,
            isLocked: true,
            canNavigateFrames: true,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false
        )
        let command = ReframerCommand.step(.forward, amount: 1)

        let activeOrigin = RegisteredHotKeyRouting.origin(isApplicationActive: true)
        XCTAssertEqual(activeOrigin, .localShortcut)
        XCTAssertFalse(
            RegisteredHotKeyRouting.shouldDeliverCarbonEvent(
                isApplicationActive: true
            )
        )
        XCTAssertTrue(ReframerCommandAvailability.isAvailable(
            command,
            origin: activeOrigin,
            context: unlocked
        ))

        let inactiveOrigin = RegisteredHotKeyRouting.origin(isApplicationActive: false)
        XCTAssertEqual(inactiveOrigin, .globalShortcut)
        XCTAssertTrue(
            RegisteredHotKeyRouting.shouldDeliverCarbonEvent(
                isApplicationActive: false
            )
        )
        XCTAssertFalse(ReframerCommandAvailability.isAvailable(
            command,
            origin: inactiveOrigin,
            context: unlocked
        ))
        XCTAssertTrue(ReframerCommandAvailability.isAvailable(
            command,
            origin: inactiveOrigin,
            context: locked
        ))

        let unavailable = ReframerCommandAvailabilityContext(
            isVideoLoaded: true,
            isLocked: true,
            canNavigateFrames: false,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false
        )
        XCTAssertFalse(ReframerCommandAvailability.isAvailable(
            command,
            origin: .localShortcut,
            context: unavailable
        ))
        XCTAssertFalse(ReframerCommandAvailability.isAvailable(
            command,
            origin: .globalShortcut,
            context: unavailable
        ))
    }

    func testActiveTextEditorOwnsRegisteredPageNavigationChord() {
        let settings = ShortcutSettings(userDefaults: defaults)
        let match = ShortcutMatch(action: .frameStepForward, variant: .primary)
        let stroke = settings.keystroke(for: match)

        XCTAssertNotNil(stroke)
        XCTAssertTrue(ShortcutControlRouting.focusedControlOwns(
            stroke: stroke!,
            kind: .textEditor
        ))
    }

    func testCustomAndSwitchRespondersKeepTheirNativeShortcuts() {
        let filterButton = FilterMenuButton(frame: .zero)
        XCTAssertTrue(ShortcutControlRouting.focusedResponderOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.space, modifiers: 0),
            responder: filterButton
        ))

        let toggle = NSSwitch()
        XCTAssertTrue(ShortcutControlRouting.focusedResponderOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.space, modifiers: 0),
            responder: toggle
        ))

        let dragHandle = WindowDragHandle(frame: .zero)
        XCTAssertTrue(ShortcutControlRouting.focusedResponderOwns(
            stroke: ShortcutKeystroke(
                keyCode: KeyCode.leftArrow,
                modifiers: NSEvent.ModifierFlags.option.rawValue
            ),
            responder: dragHandle
        ))
        XCTAssertFalse(ShortcutControlRouting.focusedResponderOwns(
            stroke: ShortcutKeystroke(keyCode: KeyCode.leftArrow, modifiers: 0),
            responder: dragHandle
        ))
    }

    @MainActor
    private func makeHostedShortcutSettingsView(
        size: NSSize
    ) -> (view: HelpView, window: NSWindow, state: VideoState) {
        let state = VideoState(defaults: defaults)
        let view = HelpView(videoState: state)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: ShortcutSettingsWindowConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        return (view, window, state)
    }

    @MainActor
    private func descendant(
        withIdentifier identifier: String,
        in view: NSView
    ) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = descendant(withIdentifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }

    private func assertAligned(
        _ origins: [CGFloat],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let first = origins.first else {
            XCTFail("Expected at least one column origin", file: file, line: line)
            return
        }
        for origin in origins.dropFirst() {
            XCTAssertEqual(origin, first, accuracy: 0.5, file: file, line: line)
        }
    }

    private func assertSuccess(
        _ result: Result<Void, ShortcutSettings.ValidationError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .failure(let error) = result {
            XCTFail("Expected success, received \(error)", file: file, line: line)
        }
    }

    private func assertFailure(
        _ expected: ShortcutSettings.ValidationError,
        from result: Result<Void, ShortcutSettings.ValidationError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("Expected \(expected), received success", file: file, line: line)
        case .failure(let actual):
            XCTAssertEqual(actual, expected, file: file, line: line)
        }
    }
}
