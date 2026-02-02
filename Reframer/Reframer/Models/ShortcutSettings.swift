import Cocoa
import Combine

/// Manages configurable keyboard shortcuts with UserDefaults persistence
class ShortcutSettings: ObservableObject {

    /// Actions that can have configurable shortcuts
    enum Action: String, CaseIterable {
        // Playback
        case playPause = "playPause"
        case frameStepForward = "frameStepForward"
        case frameStepBackward = "frameStepBackward"

        // Pan
        case panLeft = "panLeft"
        case panRight = "panRight"
        case panUp = "panUp"
        case panDown = "panDown"

        // Zoom & View
        case resetZoom = "resetZoom"
        case resetView = "resetView"

        // Window & Lock
        case toggleLock = "toggleLock"
        case globalToggleLock = "globalToggleLock"
        case showHelp = "showHelp"
        case closeModal = "closeModal"
        case toggleFilterPanel = "toggleFilterPanel"

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
            case .showHelp: return "Show help"
            case .closeModal: return "Close modal"
            case .toggleFilterPanel: return "Toggle filter panel"
            }
        }

        /// Whether this action has a multiplier variant (e.g., 10x with Shift)
        var hasMultiplierVariant: Bool {
            switch self {
            case .frameStepForward, .frameStepBackward,
                 .panLeft, .panRight, .panUp, .panDown:
                return true
            default:
                return false
            }
        }

        /// Whether this is a global shortcut (works when app not focused)
        var isGlobal: Bool {
            switch self {
            case .frameStepForward, .frameStepBackward, .globalToggleLock:
                return true
            default:
                return false
            }
        }
    }

    /// A keyboard shortcut with key code and modifier flags
    struct Shortcut: Codable, Equatable {
        var keyCode: UInt16
        var modifiers: UInt  // NSEvent.ModifierFlags.rawValue
        var multiplierModifier: UInt  // The modifier that triggers 10x variant (default: Shift)

        init(keyCode: UInt16, modifiers: UInt, multiplierModifier: UInt = NSEvent.ModifierFlags.shift.rawValue) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.multiplierModifier = multiplierModifier
        }

        var displayString: String {
            formatModifiers(modifiers) + keyCodeToString(keyCode)
        }

        var multiplierDisplayString: String {
            formatModifiers(multiplierModifier)
        }

        private func formatModifiers(_ mods: UInt) -> String {
            var parts: [String] = []
            let flags = NSEvent.ModifierFlags(rawValue: mods)
            if flags.contains(.control) { parts.append("⌃") }
            if flags.contains(.option) { parts.append("⌥") }
            if flags.contains(.shift) { parts.append("⇧") }
            if flags.contains(.command) { parts.append("⌘") }
            return parts.joined()
        }

        private func keyCodeToString(_ code: UInt16) -> String {
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
            case 51: return "Delete"
            case 117: return "⌦"
            case 48: return "Tab"
            default:
                if let char = characterForKeyCode(code) {
                    return char.uppercased()
                }
                return "Key\(code)"
            }
        }

        private func characterForKeyCode(_ code: UInt16) -> String? {
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
    }

    /// Available multiplier modifiers
    static let availableMultiplierModifiers: [(name: String, symbol: String, flags: NSEvent.ModifierFlags)] = [
        ("Shift", "⇧", .shift),
        ("Option", "⌥", .option),
        ("Control", "⌃", .control)
    ]

    /// Default shortcuts
    static let defaults: [Action: Shortcut] = [
        // Playback
        .playPause: Shortcut(keyCode: KeyCode.space, modifiers: 0),
        .frameStepForward: Shortcut(keyCode: KeyCode.pageUp, modifiers: NSEvent.ModifierFlags.command.rawValue),
        .frameStepBackward: Shortcut(keyCode: KeyCode.pageDown, modifiers: NSEvent.ModifierFlags.command.rawValue),

        // Pan (arrows, no modifiers)
        .panLeft: Shortcut(keyCode: KeyCode.leftArrow, modifiers: 0),
        .panRight: Shortcut(keyCode: KeyCode.rightArrow, modifiers: 0),
        .panUp: Shortcut(keyCode: KeyCode.upArrow, modifiers: 0),
        .panDown: Shortcut(keyCode: KeyCode.downArrow, modifiers: 0),

        // Zoom & View
        .resetZoom: Shortcut(keyCode: KeyCode.zero, modifiers: 0),
        .resetView: Shortcut(keyCode: KeyCode.r, modifiers: 0),

        // Window & Lock
        .toggleLock: Shortcut(keyCode: KeyCode.l, modifiers: 0),
        .globalToggleLock: Shortcut(keyCode: KeyCode.l, modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue),
        .showHelp: Shortcut(keyCode: KeyCode.h, modifiers: 0),
        .closeModal: Shortcut(keyCode: KeyCode.escape, modifiers: 0),
        .toggleFilterPanel: Shortcut(keyCode: KeyCode.f, modifiers: 0),
    ]

    @Published var shortcuts: [Action: Shortcut]

    private let defaultsKey = "Reframer.shortcuts.v2"

    init() {
        shortcuts = Self.defaults
        load()
    }

    /// Check if an event matches a specific action's shortcut
    func matches(event: NSEvent, action: Action) -> Bool {
        guard let shortcut = shortcuts[action] else { return false }

        let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventModifiers = event.modifierFlags.intersection(relevantModifiers)
        let shortcutModifiers = NSEvent.ModifierFlags(rawValue: shortcut.modifiers).intersection(relevantModifiers)

        return event.keyCode == shortcut.keyCode && eventModifiers == shortcutModifiers
    }

    /// Check if an event matches an action's shortcut with the multiplier modifier added
    func matchesWithMultiplier(event: NSEvent, action: Action) -> Bool {
        guard let shortcut = shortcuts[action], action.hasMultiplierVariant else { return false }

        let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventModifiers = event.modifierFlags.intersection(relevantModifiers)
        let shortcutModifiers = NSEvent.ModifierFlags(rawValue: shortcut.modifiers).intersection(relevantModifiers)
        let multiplierMod = NSEvent.ModifierFlags(rawValue: shortcut.multiplierModifier)
        let shortcutModifiersWithMultiplier = shortcutModifiers.union(multiplierMod)

        return event.keyCode == shortcut.keyCode && eventModifiers == shortcutModifiersWithMultiplier
    }

    /// Update the shortcut for an action
    func setShortcut(_ shortcut: Shortcut, for action: Action) {
        shortcuts[action] = shortcut
        save()
    }

    /// Update just the multiplier modifier for an action
    func setMultiplierModifier(_ modifier: NSEvent.ModifierFlags, for action: Action) {
        guard var shortcut = shortcuts[action] else { return }
        shortcut.multiplierModifier = modifier.rawValue
        shortcuts[action] = shortcut
        save()
    }

    /// Reset all shortcuts to defaults
    func resetToDefaults() {
        shortcuts = Self.defaults
        save()
    }

    /// Get display string for an action's current shortcut
    func displayString(for action: Action) -> String {
        shortcuts[action]?.displayString ?? "Not set"
    }

    /// Get the multiplier modifier display for an action
    func multiplierDisplayString(for action: Action) -> String {
        guard let shortcut = shortcuts[action] else { return "" }
        return shortcut.multiplierDisplayString
    }

    // MARK: - Persistence

    private func save() {
        var data: [String: [String: Any]] = [:]
        for (action, shortcut) in shortcuts {
            data[action.rawValue] = [
                "keyCode": shortcut.keyCode,
                "modifiers": shortcut.modifiers,
                "multiplierModifier": shortcut.multiplierModifier
            ]
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String: Any]] else {
            return
        }

        for action in Action.allCases {
            if let shortcutData = data[action.rawValue],
               let keyCodeNumber = shortcutData["keyCode"] as? NSNumber,
               let modifiersNumber = shortcutData["modifiers"] as? NSNumber {
                let keyCode = keyCodeNumber.uint16Value
                let modifiers = modifiersNumber.uintValue
                let multiplierModifier = (shortcutData["multiplierModifier"] as? NSNumber)?.uintValue ?? NSEvent.ModifierFlags.shift.rawValue
                shortcuts[action] = Shortcut(keyCode: keyCode, modifiers: modifiers, multiplierModifier: multiplierModifier)
            }
        }
    }
}
