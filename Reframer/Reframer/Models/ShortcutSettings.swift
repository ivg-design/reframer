import Cocoa
import Combine

enum ShortcutScope {
    case local
    case global
}

enum ShortcutVariant: Equatable, Hashable {
    case primary
    case multiplied(Int)

    var factor: Int {
        switch self {
        case .primary:
            return 1
        case .multiplied(let factor):
            return factor
        }
    }
}

struct ShortcutKeystroke: Equatable {
    let keyCode: UInt16
    let modifiers: UInt
    let isRepeat: Bool
    let charactersIgnoringModifiers: String?

    init(
        keyCode: UInt16,
        modifiers: UInt,
        isRepeat: Bool = false,
        charactersIgnoringModifiers: String? = nil
    ) {
        self.keyCode = keyCode
        self.modifiers = ShortcutSettings.normalizedModifiers(modifiers)
        self.isRepeat = isRepeat
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
    }

    init(event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.rawValue,
            isRepeat: event.isARepeat,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        )
    }
}

struct ShortcutMatch: Equatable {
    let action: ShortcutSettings.Action
    let variant: ShortcutVariant
}

enum ShortcutEventResolution: Equatable {
    case unmatched
    case consumeWithoutDispatch(ShortcutMatch)
    case dispatch(ShortcutMatch)

    var match: ShortcutMatch? {
        switch self {
        case .unmatched:
            return nil
        case .consumeWithoutDispatch(let match), .dispatch(let match):
            return match
        }
    }
}

enum ReframerCommand: Equatable {
    case openVideo
    case togglePlayPause
    case step(VideoState.FrameStepDirection, amount: Int)
    case pan(x: Double, y: Double)
    case resetZoom
    case resetView
    case toggleLock
    case toggleAlwaysOnTop
    case toggleShortcutSettings
    case toggleFilterPanel
    case closeContext
    case openDocumentation
    case toggleMinimize
}

enum ReframerCommandOrigin: Equatable {
    case localShortcut
    case globalShortcut
    case menu
}

struct ReframerCommandAvailabilityContext {
    let isVideoLoaded: Bool
    let isLocked: Bool
    let canNavigateFrames: Bool
    let isHelpVisible: Bool
    let isFilterPanelVisible: Bool
    let isDocumentationVisible: Bool
}

enum ReframerCommandAvailability {
    static func isAvailable(
        _ command: ReframerCommand,
        origin: ReframerCommandOrigin,
        context: ReframerCommandAvailabilityContext
    ) -> Bool {
        switch command {
        case .togglePlayPause:
            return context.isVideoLoaded
        case .step:
            return context.canNavigateFrames
                && (origin != .globalShortcut || context.isLocked)
        case .pan, .resetZoom, .resetView:
            return context.isVideoLoaded && !context.isLocked
        case .toggleFilterPanel:
            return context.isVideoLoaded
        case .closeContext:
            return context.isHelpVisible
                || context.isFilterPanelVisible
                || context.isDocumentationVisible
        case .openVideo, .toggleLock, .toggleAlwaysOnTop,
             .toggleShortcutSettings, .openDocumentation, .toggleMinimize:
            return true
        }
    }
}

enum RegisteredHotKeyRouting {
    static func origin(isApplicationActive: Bool) -> ReframerCommandOrigin {
        isApplicationActive ? .localShortcut : .globalShortcut
    }

    /// Carbon and AppKit both report a registered chord while Reframer is
    /// active. AppKit owns that case so focused controls retain native repeat
    /// behavior; Carbon is the sole delivery path only across applications.
    static func shouldDeliverCarbonEvent(isApplicationActive: Bool) -> Bool {
        !isApplicationActive
    }
}

enum FixedCommandShortcutResolution: Equatable {
    case unmatched
    case consumeWithoutDispatch
    case dispatch(ReframerCommand)
}

/// Command-? is reserved by AppKit for Help-menu search before a custom menu
/// item can invoke its action. Resolve the documented chord in the same local
/// event layer as configurable shortcuts, then route it through the canonical
/// command dispatcher.
enum FixedCommandShortcutRouting {
    static func eventResolution(
        stroke: ShortcutKeystroke
    ) -> FixedCommandShortcutResolution {
        let commandShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
        guard stroke.keyCode == KeyCode.questionMark,
              stroke.modifiers == ShortcutSettings.normalizedModifiers(
                commandShift
              ) else {
            return .unmatched
        }
        return stroke.isRepeat
            ? .consumeWithoutDispatch
            : .dispatch(.openDocumentation)
    }
}

struct GlobalShortcutRegistrationFailure: Equatable {
    let action: ShortcutSettings.Action
    let variant: ShortcutVariant
    let shortcut: String
    let statusCode: Int32

    var recoveryDescription: String {
        if statusCode == -9878 {
            return "\(shortcut) is already reserved by Reframer or another app."
        }
        return "\(shortcut) could not be registered (system status \(statusCode))."
    }
}

enum GlobalShortcutRegistrationStatus: Equatable {
    case pending
    case disabled
    case active(count: Int)
    case partial(registered: Int, failures: [GlobalShortcutRegistrationFailure])

    var hasFailures: Bool {
        if case .partial = self {
            return true
        }
        return false
    }
}

/// Manages validated, configurable keyboard shortcuts with versioned
/// UserDefaults persistence.
final class ShortcutSettings: ObservableObject {

    enum Action: String, CaseIterable, Codable {
        // Playback
        case playPause
        case frameStepForward
        case frameStepBackward

        // Pan
        case panLeft
        case panRight
        case panUp
        case panDown

        // Zoom & View
        case resetZoom
        case resetView

        // Window & Lock
        case toggleLock
        case globalToggleLock
        case showHelp
        case closeModal
        case toggleFilterPanel

        var displayName: String {
            switch self {
            case .playPause: return "Play / Pause"
            case .frameStepForward: return "Step frame forward"
            case .frameStepBackward: return "Step frame backward"
            case .panLeft: return "Pan left"
            case .panRight: return "Pan right"
            case .panUp: return "Pan up"
            case .panDown: return "Pan down"
            case .resetZoom: return "Reset zoom to 100%"
            case .resetView: return "Reset zoom and pan"
            case .toggleLock: return "Toggle lock mode"
            case .globalToggleLock: return "Toggle lock (global)"
            case .showHelp: return "Shortcut settings"
            case .closeModal: return "Close current panel"
            case .toggleFilterPanel: return "Toggle filter panel"
            }
        }

        var hasMultiplierVariant: Bool {
            switch self {
            case .frameStepForward, .frameStepBackward,
                 .panLeft, .panRight, .panUp, .panDown:
                return true
            default:
                return false
            }
        }

        var hasHundredVariant: Bool {
            switch self {
            case .panLeft, .panRight, .panUp, .panDown:
                return true
            default:
                return false
            }
        }

        var isGlobal: Bool {
            switch self {
            case .frameStepForward, .frameStepBackward, .globalToggleLock:
                return true
            default:
                return false
            }
        }

        var allowsKeyRepeat: Bool {
            switch self {
            case .frameStepForward, .frameStepBackward,
                 .panLeft, .panRight, .panUp, .panDown:
                return true
            default:
                return false
            }
        }

        var supportedFactors: [Int] {
            if hasHundredVariant {
                return [100, 10, 1]
            }
            if hasMultiplierVariant {
                return [10, 1]
            }
            return [1]
        }

        fileprivate func command(factor: Int) -> ReframerCommand {
            switch self {
            case .playPause:
                return .togglePlayPause
            case .frameStepForward:
                return .step(.forward, amount: factor)
            case .frameStepBackward:
                return .step(.backward, amount: factor)
            case .panLeft:
                return .pan(x: -Double(factor), y: 0)
            case .panRight:
                return .pan(x: Double(factor), y: 0)
            case .panUp:
                return .pan(x: 0, y: Double(factor))
            case .panDown:
                return .pan(x: 0, y: -Double(factor))
            case .resetZoom:
                return .resetZoom
            case .resetView:
                return .resetView
            case .toggleLock, .globalToggleLock:
                return .toggleLock
            case .showHelp:
                return .toggleShortcutSettings
            case .closeModal:
                return .closeContext
            case .toggleFilterPanel:
                return .toggleFilterPanel
            }
        }
    }

    struct Shortcut: Codable, Equatable {
        var keyCode: UInt16
        var modifiers: UInt
        var multiplierModifier: UInt
        var recordedCharacter: String?

        init(
            keyCode: UInt16,
            modifiers: UInt,
            multiplierModifier: UInt = NSEvent.ModifierFlags.shift.rawValue,
            recordedCharacter: String? = nil
        ) {
            self.keyCode = keyCode
            self.modifiers = ShortcutSettings.normalizedModifiers(modifiers)
            self.multiplierModifier = ShortcutSettings.normalizedModifiers(multiplierModifier)
            self.recordedCharacter = ShortcutSettings.sanitizedRecordedCharacter(
                recordedCharacter
            )
        }

        var displayString: String {
            displayString(factor: 1)
        }

        var multiplierDisplayString: String {
            ShortcutSettings.formatModifiers(multiplierModifier)
        }

        func displayString(factor: Int) -> String {
            let modifiers = expandedModifiers(factor: factor)
            return ShortcutSettings.formatModifiers(modifiers)
                + (recordedCharacter?.uppercased()
                    ?? ShortcutSettings.keyCodeDisplayString(keyCode))
        }

        func expandedModifiers(factor: Int) -> UInt {
            var flags = NSEvent.ModifierFlags(rawValue: modifiers)
            if factor >= 10 {
                flags.formUnion(NSEvent.ModifierFlags(rawValue: multiplierModifier))
            }
            if factor >= 100 {
                flags.insert(.command)
            }
            return ShortcutSettings.normalizedModifiers(flags.rawValue)
        }

        func menuModifierMask(factor: Int = 1) -> NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: expandedModifiers(factor: factor))
        }

        var menuKeyEquivalent: String? {
            recordedCharacter
                ?? ShortcutSettings.menuKeyEquivalent(for: keyCode)
        }
    }

    struct Binding: Codable, Equatable {
        var shortcut: Shortcut?
        var isEnabled: Bool

        init(shortcut: Shortcut?, isEnabled: Bool = true) {
            self.shortcut = shortcut
            self.isEnabled = isEnabled
        }
    }

    enum ValidationError: Error, Equatable, LocalizedError {
        case unsupportedKey
        case reservedSystemShortcut
        case duplicate(Action)
        case unsafeGlobalShortcut
        case invalidMultiplier
        case modifierCollapse
        case noShortcut

        var errorDescription: String? {
            switch self {
            case .unsupportedKey:
                return "That key cannot be used as a shortcut."
            case .reservedSystemShortcut:
                return "That shortcut is reserved by macOS or Reframer's standard menus."
            case .duplicate(let action):
                return "That shortcut conflicts with \(action.displayName)."
            case .unsafeGlobalShortcut:
                return "Global shortcuts must include Command or Control."
            case .invalidMultiplier:
                return "Choose Shift, Option, or Control for the 10× modifier."
            case .modifierCollapse:
                return "The multiplier must produce a distinct 10× and 100× shortcut."
            case .noShortcut:
                return "Assign a shortcut before enabling this action."
            }
        }
    }

    enum RecordingDisposition: Equatable {
        case notRecording
        case consumed
        case saved
        case rejected(ValidationError)
    }

    private struct PersistenceEnvelope: Codable {
        let schemaVersion: Int
        let bindings: [String: Binding]
        let globalShortcutsEnabled: Bool?
    }

    private struct StrokeSignature: Hashable {
        let keyCode: UInt16
        let modifiers: UInt
    }

    static let persistenceKey = "Reframer.shortcuts.v3"
    static let legacyPersistenceKey = "Reframer.shortcuts.v2"
    private static let schemaVersion = 3
    private static let relevantModifiers: NSEvent.ModifierFlags = [
        .command, .shift, .option, .control
    ]

    static let availableMultiplierModifiers: [
        (name: String, symbol: String, flags: NSEvent.ModifierFlags)
    ] = [
        ("Shift", "⇧", .shift),
        ("Option", "⌥", .option),
        ("Control", "⌃", .control)
    ]

    /// Product-contract defaults. Page Down advances; Page Up reverses.
    static let defaults: [Action: Binding] = [
        .playPause: Binding(shortcut: Shortcut(keyCode: KeyCode.space, modifiers: 0)),
        .frameStepForward: Binding(shortcut: Shortcut(
            keyCode: KeyCode.pageDown,
            modifiers: NSEvent.ModifierFlags.command.rawValue
        )),
        .frameStepBackward: Binding(shortcut: Shortcut(
            keyCode: KeyCode.pageUp,
            modifiers: NSEvent.ModifierFlags.command.rawValue
        )),

        .panLeft: Binding(shortcut: Shortcut(keyCode: KeyCode.leftArrow, modifiers: 0)),
        .panRight: Binding(shortcut: Shortcut(keyCode: KeyCode.rightArrow, modifiers: 0)),
        .panUp: Binding(shortcut: Shortcut(keyCode: KeyCode.upArrow, modifiers: 0)),
        .panDown: Binding(shortcut: Shortcut(keyCode: KeyCode.downArrow, modifiers: 0)),

        .resetZoom: Binding(shortcut: Shortcut(keyCode: KeyCode.zero, modifiers: 0)),
        .resetView: Binding(shortcut: Shortcut(keyCode: KeyCode.r, modifiers: 0)),

        .toggleLock: Binding(shortcut: Shortcut(keyCode: KeyCode.l, modifiers: 0)),
        .globalToggleLock: Binding(shortcut: Shortcut(
            keyCode: KeyCode.l,
            modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue
        )),
        .showHelp: Binding(shortcut: Shortcut(keyCode: KeyCode.h, modifiers: 0)),
        .closeModal: Binding(shortcut: Shortcut(keyCode: KeyCode.escape, modifiers: 0)),
        .toggleFilterPanel: Binding(shortcut: Shortcut(keyCode: KeyCode.f, modifiers: 0))
    ]

    @Published private(set) var bindings: [Action: Binding]
    @Published private(set) var globalShortcutsEnabled: Bool
    @Published private(set) var recordingAction: Action?
    @Published private(set) var validationMessage: String?
    @Published private(set) var globalRegistrationStatus: GlobalShortcutRegistrationStatus

    private let userDefaults: UserDefaults

    /// Compatibility view for consumers that only need assigned shortcuts.
    var shortcuts: [Action: Shortcut] {
        bindings.reduce(into: [:]) { result, entry in
            if let shortcut = entry.value.shortcut {
                result[entry.key] = shortcut
            }
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.bindings = Self.defaults
        self.globalShortcutsEnabled = true
        self.globalRegistrationStatus = .pending
        load()
    }

    private init(validationOnly: Bool) {
        self.userDefaults = .standard
        self.bindings = [:]
        self.globalShortcutsEnabled = true
        self.globalRegistrationStatus = .pending
    }

    func binding(for action: Action) -> Binding {
        bindings[action] ?? Self.defaults[action]!
    }

    func displayString(for action: Action) -> String {
        let binding = binding(for: action)
        guard binding.isEnabled else { return "Disabled" }
        return binding.shortcut?.displayString ?? "Not set"
    }

    func multiplierDisplayString(for action: Action) -> String {
        binding(for: action).shortcut?.multiplierDisplayString ?? ""
    }

    func resolve(stroke: ShortcutKeystroke, scope: ShortcutScope) -> ShortcutMatch? {
        guard case .dispatch(let match) = eventResolution(stroke: stroke, scope: scope) else {
            return nil
        }
        return match
    }

    /// Separates shortcut identity from repeat dispatch policy. A repeat for a
    /// recognized non-repeating action is still consumed so it cannot leak into
    /// an equivalent AppKit menu item and invoke the action there.
    func eventResolution(
        stroke: ShortcutKeystroke,
        scope: ShortcutScope
    ) -> ShortcutEventResolution {
        if scope == .global && !globalShortcutsEnabled {
            return .unmatched
        }
        for action in Action.allCases {
            guard scope == .local || action.isGlobal else { continue }
            guard let binding = bindings[action],
                  binding.isEnabled,
                  let shortcut = binding.shortcut else {
                continue
            }

            for factor in action.supportedFactors {
                guard stroke.keyCode == shortcut.keyCode,
                      stroke.modifiers == shortcut.expandedModifiers(factor: factor) else {
                    continue
                }
                let match = ShortcutMatch(
                    action: action,
                    variant: factor == 1 ? .primary : .multiplied(factor)
                )
                if stroke.isRepeat && !action.allowsKeyRepeat {
                    return .consumeWithoutDispatch(match)
                }
                return .dispatch(match)
            }
        }
        return .unmatched
    }

    func command(for match: ShortcutMatch) -> ReframerCommand {
        match.action.command(factor: match.variant.factor)
    }

    func keystroke(for match: ShortcutMatch, isRepeat: Bool = false) -> ShortcutKeystroke? {
        guard let shortcut = binding(for: match.action).shortcut else { return nil }
        return ShortcutKeystroke(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.expandedModifiers(factor: match.variant.factor),
            isRepeat: isRepeat
        )
    }

    @discardableResult
    func setShortcut(_ shortcut: Shortcut, for action: Action) -> Result<Void, ValidationError> {
        let normalized = Shortcut(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifiers,
            multiplierModifier: shortcut.multiplierModifier,
            recordedCharacter: shortcut.recordedCharacter
        )

        do {
            try validate(normalized, for: action, existingBindings: bindings)
            var updated = bindings
            updated[action] = Binding(shortcut: normalized, isEnabled: true)
            bindings = updated
            validationMessage = nil
            save()
            return .success(())
        } catch let error as ValidationError {
            validationMessage = error.localizedDescription
            return .failure(error)
        } catch {
            validationMessage = error.localizedDescription
            return .failure(.unsupportedKey)
        }
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool, for action: Action) -> Result<Void, ValidationError> {
        var binding = binding(for: action)
        if isEnabled {
            guard let shortcut = binding.shortcut else {
                validationMessage = ValidationError.noShortcut.localizedDescription
                return .failure(.noShortcut)
            }
            do {
                try validate(shortcut, for: action, existingBindings: bindings)
            } catch let error as ValidationError {
                validationMessage = error.localizedDescription
                return .failure(error)
            } catch {
                validationMessage = error.localizedDescription
                return .failure(.unsupportedKey)
            }
        }

        binding.isEnabled = isEnabled
        var updated = bindings
        updated[action] = binding
        bindings = updated
        validationMessage = nil
        save()
        return .success(())
    }

    func clearShortcut(for action: Action) {
        var updated = bindings
        updated[action] = Binding(shortcut: nil, isEnabled: true)
        bindings = updated
        if recordingAction == action {
            recordingAction = nil
        }
        validationMessage = nil
        save()
    }

    @discardableResult
    func setMultiplierModifier(
        _ modifier: NSEvent.ModifierFlags,
        for action: Action
    ) -> Result<Void, ValidationError> {
        guard var shortcut = binding(for: action).shortcut else {
            validationMessage = ValidationError.noShortcut.localizedDescription
            return .failure(.noShortcut)
        }
        shortcut.multiplierModifier = Self.normalizedModifiers(modifier.rawValue)
        return setShortcut(shortcut, for: action)
    }

    func resetToDefaults() {
        bindings = Self.defaults
        globalShortcutsEnabled = true
        recordingAction = nil
        validationMessage = nil
        save()
    }

    func setGlobalShortcutsEnabled(_ isEnabled: Bool) {
        globalShortcutsEnabled = isEnabled
        globalRegistrationStatus = isEnabled ? .pending : .disabled
        save()
    }

    func setGlobalRegistrationStatus(_ status: GlobalShortcutRegistrationStatus) {
        globalRegistrationStatus = status
    }

    func beginRecording(for action: Action) {
        recordingAction = action
        validationMessage = nil
    }

    func cancelRecording() {
        recordingAction = nil
        validationMessage = nil
    }

    func record(stroke: ShortcutKeystroke) -> RecordingDisposition {
        guard let action = recordingAction else { return .notRecording }

        if stroke.keyCode == KeyCode.escape {
            cancelRecording()
            return .consumed
        }

        if stroke.keyCode == KeyCode.delete || stroke.keyCode == KeyCode.forwardDelete {
            clearShortcut(for: action)
            recordingAction = nil
            return .consumed
        }

        let multiplier = binding(for: action).shortcut?.multiplierModifier
            ?? NSEvent.ModifierFlags.shift.rawValue
        let candidate = Shortcut(
            keyCode: stroke.keyCode,
            modifiers: stroke.modifiers,
            multiplierModifier: multiplier,
            recordedCharacter: stroke.charactersIgnoringModifiers
        )
        switch setShortcut(candidate, for: action) {
        case .success:
            recordingAction = nil
            return .saved
        case .failure(let error):
            return .rejected(error)
        }
    }

    // MARK: - Validation

    private func validate(
        _ shortcut: Shortcut,
        for action: Action,
        existingBindings: [Action: Binding]
    ) throws {
        guard Self.isSupportedKeyCode(shortcut.keyCode) else {
            throw ValidationError.unsupportedKey
        }

        let primaryModifiers = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
        if action.isGlobal,
           primaryModifiers.intersection([.command, .control]).isEmpty {
            throw ValidationError.unsafeGlobalShortcut
        }

        if action.hasMultiplierVariant {
            let multiplier = NSEvent.ModifierFlags(rawValue: shortcut.multiplierModifier)
            let allowed: NSEvent.ModifierFlags = [.shift, .option, .control]
            guard !multiplier.isEmpty,
                  multiplier.subtracting(allowed).isEmpty,
                  multiplier.rawValue.nonzeroBitCount == 1 else {
                throw ValidationError.invalidMultiplier
            }
            guard primaryModifiers.intersection(multiplier).isEmpty else {
                throw ValidationError.modifierCollapse
            }
            if action.hasHundredVariant,
               primaryModifiers.contains(.command) || multiplier.contains(.command) {
                throw ValidationError.modifierCollapse
            }
        }

        let candidateStrokes = Set(action.supportedFactors.map {
            StrokeSignature(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.expandedModifiers(factor: $0)
            )
        })
        guard candidateStrokes.count == action.supportedFactors.count else {
            throw ValidationError.modifierCollapse
        }

        if candidateStrokes.contains(where: Self.reservedSystemStrokes.contains) {
            throw ValidationError.reservedSystemShortcut
        }

        for otherAction in Action.allCases where otherAction != action {
            guard let otherBinding = existingBindings[otherAction],
                  otherBinding.isEnabled,
                  let otherShortcut = otherBinding.shortcut else {
                continue
            }
            let otherStrokes = Set(otherAction.supportedFactors.map {
                StrokeSignature(
                    keyCode: otherShortcut.keyCode,
                    modifiers: otherShortcut.expandedModifiers(factor: $0)
                )
            })
            if !candidateStrokes.isDisjoint(with: otherStrokes) {
                throw ValidationError.duplicate(otherAction)
            }
        }
    }

    private static func sanitizedBindings(_ raw: [Action: Binding]) -> [Action: Binding] {
        var sanitized: [Action: Binding] = [:]
        let validator = ShortcutSettings(validationOnly: true)

        for action in Action.allCases {
            let candidate = raw[action] ?? defaults[action]!
            guard candidate.isEnabled, let shortcut = candidate.shortcut else {
                sanitized[action] = candidate
                continue
            }

            let normalized = Shortcut(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                multiplierModifier: shortcut.multiplierModifier,
                recordedCharacter: shortcut.recordedCharacter
            )
            do {
                try validator.validate(normalized, for: action, existingBindings: sanitized)
                sanitized[action] = Binding(shortcut: normalized, isEnabled: true)
            } catch {
                if raw[action] != nil {
                    // Preserve a restored custom chord for repair, but never
                    // activate data that fails current validation.
                    sanitized[action] = Binding(shortcut: normalized, isEnabled: false)
                } else {
                    let fallback = defaults[action]!
                    if let fallbackShortcut = fallback.shortcut,
                       (try? validator.validate(
                           fallbackShortcut,
                           for: action,
                           existingBindings: sanitized
                       )) != nil {
                        sanitized[action] = fallback
                    } else {
                        sanitized[action] = Binding(
                            shortcut: fallback.shortcut,
                            isEnabled: false
                        )
                    }
                }
            }
        }

        return sanitized
    }

    // MARK: - Persistence

    private func save() {
        let encodedBindings = Dictionary(uniqueKeysWithValues: bindings.map {
            ($0.key.rawValue, $0.value)
        })
        let envelope = PersistenceEnvelope(
            schemaVersion: Self.schemaVersion,
            bindings: encodedBindings,
            globalShortcutsEnabled: globalShortcutsEnabled
        )
        if let data = try? JSONEncoder().encode(envelope) {
            userDefaults.set(data, forKey: Self.persistenceKey)
        }
    }

    private func load() {
        if let data = userDefaults.data(forKey: Self.persistenceKey),
           let envelope = try? JSONDecoder().decode(PersistenceEnvelope.self, from: data),
           envelope.schemaVersion == Self.schemaVersion {
            let decoded: [Action: Binding] = Dictionary(
                uniqueKeysWithValues: envelope.bindings.compactMap {
                guard let action = Action(rawValue: $0.key) else { return nil }
                return (action, $0.value)
            })
            bindings = Self.sanitizedBindings(decoded)
            globalShortcutsEnabled = envelope.globalShortcutsEnabled ?? true
            return
        }

        guard let legacy = userDefaults.dictionary(forKey: Self.legacyPersistenceKey) else {
            return
        }

        var migrated = Self.defaults
        for action in Action.allCases {
            guard let shortcutData = legacy[action.rawValue] as? [String: Any],
                  let keyCodeNumber = shortcutData["keyCode"] as? NSNumber,
                  let modifiersNumber = shortcutData["modifiers"] as? NSNumber else {
                continue
            }
            let multiplierNumber = shortcutData["multiplierModifier"] as? NSNumber
            migrated[action] = Binding(shortcut: Shortcut(
                keyCode: keyCodeNumber.uint16Value,
                modifiers: modifiersNumber.uintValue,
                multiplierModifier: multiplierNumber?.uintValue
                    ?? NSEvent.ModifierFlags.shift.rawValue
            ))
        }

        // v2 shipped the Page Up/Page Down meanings backwards. Only repair the
        // exact untouched pair; customized users retain their chosen chords.
        let oldForward = Shortcut(
            keyCode: KeyCode.pageUp,
            modifiers: NSEvent.ModifierFlags.command.rawValue
        )
        let oldBackward = Shortcut(
            keyCode: KeyCode.pageDown,
            modifiers: NSEvent.ModifierFlags.command.rawValue
        )
        if migrated[.frameStepForward]?.shortcut == oldForward,
           migrated[.frameStepBackward]?.shortcut == oldBackward {
            migrated[.frameStepForward] = Self.defaults[.frameStepForward]
            migrated[.frameStepBackward] = Self.defaults[.frameStepBackward]
        }

        bindings = Self.sanitizedBindings(migrated)
        globalShortcutsEnabled = true
        save()
    }

    // MARK: - Formatting

    static func normalizedModifiers(_ rawValue: UInt) -> UInt {
        NSEvent.ModifierFlags(rawValue: rawValue)
            .intersection(relevantModifiers)
            .rawValue
    }

    private static func formatModifiers(_ rawValue: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: rawValue)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    private static func keyCodeDisplayString(_ code: UInt16) -> String {
        switch code {
        case KeyCode.pageUp: return "PgUp"
        case KeyCode.pageDown: return "PgDn"
        case KeyCode.space: return "Space"
        case KeyCode.escape: return "Esc"
        case KeyCode.returnKey: return "Return"
        case KeyCode.leftArrow: return "←"
        case KeyCode.rightArrow: return "→"
        case KeyCode.upArrow: return "↑"
        case KeyCode.downArrow: return "↓"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 115: return "Home"
        case 119: return "End"
        case KeyCode.delete: return "Delete"
        case KeyCode.forwardDelete: return "⌦"
        case 48: return "Tab"
        default:
            return characterForKeyCode(code)?.uppercased() ?? "Key\(code)"
        }
    }

    static func menuKeyEquivalent(for code: UInt16) -> String? {
        switch code {
        case 122:
            return functionKeyEquivalent(NSF1FunctionKey)
        case 120:
            return functionKeyEquivalent(NSF2FunctionKey)
        case 99:
            return functionKeyEquivalent(NSF3FunctionKey)
        case 118:
            return functionKeyEquivalent(NSF4FunctionKey)
        case 96:
            return functionKeyEquivalent(NSF5FunctionKey)
        case 97:
            return functionKeyEquivalent(NSF6FunctionKey)
        case 98:
            return functionKeyEquivalent(NSF7FunctionKey)
        case 100:
            return functionKeyEquivalent(NSF8FunctionKey)
        case 101:
            return functionKeyEquivalent(NSF9FunctionKey)
        case 109:
            return functionKeyEquivalent(NSF10FunctionKey)
        case 103:
            return functionKeyEquivalent(NSF11FunctionKey)
        case 111:
            return functionKeyEquivalent(NSF12FunctionKey)
        case KeyCode.home:
            return functionKeyEquivalent(NSHomeFunctionKey)
        case KeyCode.end:
            return functionKeyEquivalent(NSEndFunctionKey)
        case KeyCode.pageUp:
            return functionKeyEquivalent(NSPageUpFunctionKey)
        case KeyCode.pageDown:
            return functionKeyEquivalent(NSPageDownFunctionKey)
        case KeyCode.leftArrow:
            return functionKeyEquivalent(NSLeftArrowFunctionKey)
        case KeyCode.rightArrow:
            return functionKeyEquivalent(NSRightArrowFunctionKey)
        case KeyCode.upArrow:
            return functionKeyEquivalent(NSUpArrowFunctionKey)
        case KeyCode.downArrow:
            return functionKeyEquivalent(NSDownArrowFunctionKey)
        case KeyCode.space:
            return " "
        case KeyCode.escape:
            return "\u{1b}"
        case KeyCode.returnKey:
            return "\r"
        case KeyCode.tab:
            return "\t"
        case KeyCode.delete:
            return "\u{8}"
        case KeyCode.forwardDelete:
            return functionKeyEquivalent(NSDeleteFunctionKey)
        default:
            return characterForKeyCode(code)
        }
    }

    private static func functionKeyEquivalent(_ value: Int) -> String {
        String(Character(UnicodeScalar(value)!))
    }

    private static func sanitizedRecordedCharacter(_ value: String?) -> String? {
        guard let value,
              value.count == 1,
              let scalar = value.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar),
              scalar.value < 0xF700 else {
            return nil
        }
        return value
    }

    private static func characterForKeyCode(_ code: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
            38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "n", 46: "m", 47: "."
        ]
        return keyMap[code]
    }

    private static func isSupportedKeyCode(_ keyCode: UInt16) -> Bool {
        guard keyCode <= 127 else { return false }
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        return keyCode != KeyCode.tab && !modifierKeyCodes.contains(keyCode)
    }

    private static let reservedSystemStrokes: Set<StrokeSignature> = {
        let command = NSEvent.ModifierFlags.command.rawValue
        let commandShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
        let commandOption = NSEvent.ModifierFlags([.command, .option]).rawValue
        let control = NSEvent.ModifierFlags.control.rawValue
        return [
            StrokeSignature(keyCode: 12, modifiers: command),       // Quit
            StrokeSignature(keyCode: 13, modifiers: command),       // Close
            StrokeSignature(keyCode: KeyCode.h, modifiers: command),
            StrokeSignature(keyCode: 46, modifiers: command),       // Minimize
            StrokeSignature(keyCode: KeyCode.o, modifiers: command),
            StrokeSignature(keyCode: 43, modifiers: command),       // Preferences
            StrokeSignature(keyCode: KeyCode.h, modifiers: commandOption),
            StrokeSignature(keyCode: KeyCode.space, modifiers: command),
            StrokeSignature(keyCode: 48, modifiers: command),
            StrokeSignature(keyCode: 7, modifiers: command),        // Cut
            StrokeSignature(keyCode: 8, modifiers: command),        // Copy
            StrokeSignature(keyCode: 9, modifiers: command),        // Paste
            StrokeSignature(keyCode: KeyCode.a, modifiers: command),
            StrokeSignature(keyCode: 6, modifiers: command),        // Undo
            StrokeSignature(keyCode: 6, modifiers: commandShift),   // Redo
            StrokeSignature(keyCode: KeyCode.questionMark, modifiers: commandShift),
            StrokeSignature(keyCode: KeyCode.space, modifiers: control),
            StrokeSignature(keyCode: KeyCode.leftArrow, modifiers: control),
            StrokeSignature(keyCode: KeyCode.rightArrow, modifiers: control),
            StrokeSignature(keyCode: KeyCode.upArrow, modifiers: control),
            StrokeSignature(keyCode: KeyCode.downArrow, modifiers: control)
        ]
    }()
}
