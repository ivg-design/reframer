import Cocoa

protocol ReframerShortcutOwningResponder: AnyObject {
    /// Returns true when this responder's documented native interaction owns
    /// the chord before Reframer's configurable command layer sees it.
    func ownsReframerShortcut(_ stroke: ShortcutKeystroke) -> Bool
}

/// Marks a read-only content surface whose unmodified navigation keys should
/// remain native while Reframer's modified application shortcuts stay active.
protocol ReframerNavigableContentResponder: AnyObject {}

enum FocusedControlKind {
    case none
    case textEditor
    case button
    case slider
    case popUpButton
    case navigableContent
    case otherControl
}

enum ShortcutControlRouting {
    static func kind(for responder: NSResponder?) -> FocusedControlKind {
        if responderIsInsideNavigableContent(responder) {
            return .navigableContent
        }
        switch responder {
        case is NSTextView:
            return .textEditor
        case is NSTableView, is NSCollectionView, is NSBrowser:
            return .navigableContent
        case is NSPopUpButton:
            return .popUpButton
        case is NSSwitch:
            return .button
        case is NSButton:
            return .button
        case is NSSlider:
            return .slider
        case is NSControl:
            return .otherControl
        default:
            return .none
        }
    }

    static func focusedResponderOwns(
        stroke: ShortcutKeystroke,
        responder: NSResponder?
    ) -> Bool {
        if let owner = responder as? ReframerShortcutOwningResponder,
           owner.ownsReframerShortcut(stroke) {
            return true
        }
        return focusedControlOwns(stroke: stroke, kind: kind(for: responder))
    }

    /// Returns true only when AppKit convention assigns this key to the
    /// focused control. Product shortcuts remain available while a control is
    /// focused unless activation, navigation, or text editing owns the key.
    static func focusedControlOwns(
        stroke: ShortcutKeystroke,
        kind: FocusedControlKind
    ) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: stroke.modifiers)
        let hasCommand = flags.contains(.command)
        let hasControl = flags.contains(.control)

        switch kind {
        case .none:
            return false
        case .textEditor:
            if hasCommand {
                return isStandardTextCommand(stroke)
                    || isTextNavigationKey(stroke.keyCode)
            }
            // Option produces alternate text and Control participates in
            // Cocoa text bindings, so both remain native while editing.
            return true
        case .button:
            return !hasCommand && !hasControl
                && [KeyCode.space, KeyCode.returnKey].contains(stroke.keyCode)
        case .slider:
            return !hasCommand && !hasControl && [
                KeyCode.leftArrow, KeyCode.rightArrow,
                KeyCode.upArrow, KeyCode.downArrow,
                KeyCode.pageUp, KeyCode.pageDown,
                KeyCode.home, KeyCode.end
            ].contains(stroke.keyCode)
        case .popUpButton:
            return !hasCommand && !hasControl && [
                KeyCode.space, KeyCode.returnKey, KeyCode.escape,
                KeyCode.upArrow, KeyCode.downArrow
            ].contains(stroke.keyCode)
        case .navigableContent:
            return !hasCommand && !hasControl && [
                KeyCode.space, KeyCode.returnKey,
                KeyCode.leftArrow, KeyCode.rightArrow,
                KeyCode.upArrow, KeyCode.downArrow,
                KeyCode.pageUp, KeyCode.pageDown,
                KeyCode.home, KeyCode.end
            ].contains(stroke.keyCode)
        case .otherControl:
            return false
        }
    }

    private static func responderIsInsideNavigableContent(
        _ responder: NSResponder?
    ) -> Bool {
        var view = responder as? NSView
        while let currentView = view {
            if currentView is ReframerNavigableContentResponder {
                return true
            }
            view = currentView.superview
        }
        return false
    }

    private static func isTextNavigationKey(_ keyCode: UInt16) -> Bool {
        [
            KeyCode.leftArrow, KeyCode.rightArrow,
            KeyCode.upArrow, KeyCode.downArrow,
            KeyCode.pageUp, KeyCode.pageDown,
            KeyCode.home, KeyCode.end,
            KeyCode.delete, KeyCode.forwardDelete,
            KeyCode.returnKey, KeyCode.tab, KeyCode.escape
        ].contains(keyCode)
    }

    private static func isStandardTextCommand(_ stroke: ShortcutKeystroke) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: stroke.modifiers)
        let command = NSEvent.ModifierFlags.command
        let commandShift: NSEvent.ModifierFlags = [.command, .shift]
        switch stroke.keyCode {
        case KeyCode.a, KeyCode.x, KeyCode.c, KeyCode.v:
            return flags == command
        case KeyCode.z:
            return flags == command || flags == commandShift
        default:
            return false
        }
    }
}
