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
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false
        )
        let locked = ReframerCommandAvailabilityContext(
            isVideoLoaded: true,
            isLocked: true,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false
        )
        let command = ReframerCommand.step(.forward, amount: 1)

        let activeOrigin = RegisteredHotKeyRouting.origin(isApplicationActive: true)
        XCTAssertEqual(activeOrigin, .localShortcut)
        XCTAssertTrue(ReframerCommandAvailability.isAvailable(
            command,
            origin: activeOrigin,
            context: unlocked
        ))

        let inactiveOrigin = RegisteredHotKeyRouting.origin(isApplicationActive: false)
        XCTAssertEqual(inactiveOrigin, .globalShortcut)
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
