import Carbon
import Cocoa

struct GlobalHotKeyDescriptor: Equatable {
    let identifier: UInt32
    let match: ShortcutMatch
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayString: String
    let allowsRepeat: Bool
}

struct GlobalHotKeyRegistrationChanges: Equatable {
    let retainedIdentifiers: Set<UInt32>
    let removedIdentifiers: Set<UInt32>
    let addedIdentifiers: Set<UInt32>

    static func between(
        current: [UInt32: GlobalHotKeyDescriptor],
        desired: [UInt32: GlobalHotKeyDescriptor]
    ) -> GlobalHotKeyRegistrationChanges {
        let unchanged = Set(current.compactMap { identifier, descriptor in
            desired[identifier] == descriptor ? identifier : nil
        })
        return GlobalHotKeyRegistrationChanges(
            retainedIdentifiers: unchanged,
            removedIdentifiers: Set(current.keys).subtracting(unchanged),
            addedIdentifiers: Set(desired.keys).subtracting(unchanged)
        )
    }
}

/// Safety gate for a window that becomes completely pointer-transparent.
/// Unlocking is unconditional; entering or remaining locked requires the
/// exact global recovery chord to be registered.
enum LockModeRecoveryPolicy {
    static func canToggle(
        isCurrentlyLocked: Bool,
        isRecoveryRegistered: Bool
    ) -> Bool {
        isCurrentlyLocked || isRecoveryRegistered
    }

    static func requiresForcedUnlock(
        isCurrentlyLocked: Bool,
        isRecoveryRegistered: Bool
    ) -> Bool {
        isCurrentlyLocked && !isRecoveryRegistered
    }
}

enum GlobalHotKeyPlan {
    static func descriptors(
        for settings: ShortcutSettings,
        includeFrameSteps: Bool = true
    ) -> [GlobalHotKeyDescriptor] {
        guard settings.globalShortcutsEnabled else { return [] }

        var descriptors: [GlobalHotKeyDescriptor] = []

        for action in ShortcutSettings.Action.allCases where action.isGlobal {
            if !includeFrameSteps,
               action == .frameStepForward || action == .frameStepBackward {
                continue
            }
            let binding = settings.binding(for: action)
            guard binding.isEnabled, let shortcut = binding.shortcut else { continue }

            for factor in action.supportedFactors.sorted() {
                descriptors.append(GlobalHotKeyDescriptor(
                    identifier: identifier(for: action, factor: factor),
                    match: ShortcutMatch(
                        action: action,
                        variant: factor == 1 ? .primary : .multiplied(factor)
                    ),
                    keyCode: UInt32(shortcut.keyCode),
                    carbonModifiers: carbonModifiers(
                        from: shortcut.expandedModifiers(factor: factor)
                    ),
                    displayString: shortcut.displayString(factor: factor),
                    allowsRepeat: action.allowsKeyRepeat
                ))
            }
        }

        return descriptors
    }

    private static func identifier(
        for action: ShortcutSettings.Action,
        factor: Int
    ) -> UInt32 {
        switch (action, factor) {
        case (.frameStepForward, 1): return 1
        case (.frameStepForward, 10): return 2
        case (.frameStepBackward, 1): return 3
        case (.frameStepBackward, 10): return 4
        case (.globalToggleLock, 1): return 5
        default:
            preconditionFailure("Unsupported global hot-key variant")
        }
    }

    static func carbonModifiers(from appKitModifiers: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: appKitModifiers)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

/// Tracks physical down/up state for registered shortcuts that must dispatch
/// only once per key press.
struct GlobalHotKeyPressState {
    private(set) var pressedNonRepeatingIdentifiers: Set<UInt32> = []

    mutating func shouldDeliverPress(
        identifier: UInt32,
        allowsRepeat: Bool
    ) -> Bool {
        guard !allowsRepeat else { return true }
        return pressedNonRepeatingIdentifiers.insert(identifier).inserted
    }

    mutating func release(identifier: UInt32) {
        pressedNonRepeatingIdentifiers.remove(identifier)
    }

    mutating func reset() {
        pressedNonRepeatingIdentifiers.removeAll()
    }
}

/// Registers a finite set of exclusive system hot keys. Unlike a global event
/// monitor, this API reports only the exact chords Reframer declares and does
/// not require Accessibility or Input Monitoring permission.
final class GlobalHotKeyRegistrar {
    typealias Handler = (ShortcutMatch) -> Void

    private struct Registration {
        let descriptor: GlobalHotKeyDescriptor
        let reference: EventHotKeyRef
    }

    private static let signature: OSType = 0x5266484B // "RfHK"

    private let handler: Handler
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]
    private var pressState = GlobalHotKeyPressState()

    init(handler: @escaping Handler) {
        self.handler = handler
        installEventHandler()
    }

    deinit {
        invalidate()
    }

    func apply(
        settings: ShortcutSettings,
        includeFrameSteps: Bool,
        suspended: Bool = false
    ) -> GlobalShortcutRegistrationStatus {
        guard settings.globalShortcutsEnabled else {
            unregisterAll()
            return .disabled
        }
        guard !suspended else {
            unregisterAll()
            return .pending
        }
        if eventHandler == nil {
            installEventHandler()
        }
        guard eventHandler != nil else {
            let failures = GlobalHotKeyPlan.descriptors(
                for: settings,
                includeFrameSteps: includeFrameSteps
            ).map {
                GlobalShortcutRegistrationFailure(
                    action: $0.match.action,
                    variant: $0.match.variant,
                    shortcut: $0.displayString,
                    statusCode: Int32(eventInternalErr)
                )
            }
            unregisterAll()
            return .partial(registered: 0, failures: failures)
        }

        let desiredDescriptors = GlobalHotKeyPlan.descriptors(
            for: settings,
            includeFrameSteps: includeFrameSteps
        )
        let desiredByIdentifier = Dictionary(
            uniqueKeysWithValues: desiredDescriptors.map {
                ($0.identifier, $0)
            }
        )
        let changes = GlobalHotKeyRegistrationChanges.between(
            current: registrations.mapValues { $0.descriptor },
            desired: desiredByIdentifier
        )

        for identifier in changes.removedIdentifiers {
            guard let registration = registrations.removeValue(
                forKey: identifier
            ) else {
                continue
            }
            UnregisterEventHotKey(registration.reference)
            pressState.release(identifier: identifier)
        }

        var failures: [GlobalShortcutRegistrationFailure] = []
        for descriptor in desiredDescriptors
        where changes.addedIdentifiers.contains(descriptor.identifier) {
            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: Self.signature,
                id: descriptor.identifier
            )
            let status = RegisterEventHotKey(
                descriptor.keyCode,
                descriptor.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive),
                &reference
            )

            if status == noErr, let reference {
                registrations[descriptor.identifier] = Registration(
                    descriptor: descriptor,
                    reference: reference
                )
            } else {
                failures.append(GlobalShortcutRegistrationFailure(
                    action: descriptor.match.action,
                    variant: descriptor.match.variant,
                    shortcut: descriptor.displayString,
                    statusCode: status
                ))
            }
        }

        if failures.isEmpty {
            return .active(count: registrations.count)
        }
        return .partial(registered: registrations.count, failures: failures)
    }

    func isRegistered(match: ShortcutMatch) -> Bool {
        registrations.values.contains { $0.descriptor.match == match }
    }

    func invalidate() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let registrar = Unmanaged<GlobalHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return registrar.handle(event: event)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            eventHandler = nil
        }
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == Self.signature,
              let registration = registrations[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            if !pressState.shouldDeliverPress(
                identifier: hotKeyID.id,
                allowsRepeat: registration.descriptor.allowsRepeat
            ) {
                return noErr
            }
            deliver(registration.descriptor.match)
        case UInt32(kEventHotKeyReleased):
            pressState.release(identifier: hotKeyID.id)
        default:
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    private func deliver(_ match: ShortcutMatch) {
        if Thread.isMainThread {
            handler(match)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handler(match)
            }
        }
    }

    private func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
        pressState.reset()
    }
}
