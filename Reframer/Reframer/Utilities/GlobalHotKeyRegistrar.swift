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
    private var pressedNonRepeatingIdentifiers: Set<UInt32> = []

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
        unregisterAll()

        guard settings.globalShortcutsEnabled else {
            return .disabled
        }
        guard !suspended else {
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
            return .partial(registered: 0, failures: failures)
        }

        var failures: [GlobalShortcutRegistrationFailure] = []
        for descriptor in GlobalHotKeyPlan.descriptors(
            for: settings,
            includeFrameSteps: includeFrameSteps
        ) {
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
            if !registration.descriptor.allowsRepeat,
               !pressedNonRepeatingIdentifiers.insert(hotKeyID.id).inserted {
                return noErr
            }
            deliver(registration.descriptor.match)
        case UInt32(kEventHotKeyReleased):
            pressedNonRepeatingIdentifiers.remove(hotKeyID.id)
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
        pressedNonRepeatingIdentifiers.removeAll()
    }
}
