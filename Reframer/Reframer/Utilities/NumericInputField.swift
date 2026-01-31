import SwiftUI
import AppKit

struct NumericInputField: NSViewRepresentable {
    @Binding var text: String
    let min: Double
    let max: Double
    let allowsDecimal: Bool
    let step: Double
    let shiftStep: Double
    let cmdStep: Double?
    let decimalPlaces: Int
    let font: NSFont
    let alignment: NSTextAlignment
    let isEnabled: Bool
    let onValueChange: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = IncrementingTextField()
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = font
        field.alignment = alignment
        field.isEditable = true
        field.isSelectable = true
        field.delegate = context.coordinator
        field.isEnabled = isEnabled
        context.coordinator.textField = field
        field.keyDownHandler = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.font = font
        nsView.alignment = alignment
        nsView.isEnabled = isEnabled
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        private let parent: NumericInputField
        weak var textField: NSTextField?

        init(_ parent: NumericInputField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            if let editor = obj.userInfo?["NSFieldEditor"] as? NSTextView {
                editor.delegate = self
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let filtered = filterText(field.stringValue)
            if filtered != field.stringValue {
                field.stringValue = filtered
            }
            parent.text = filtered
            applyValue(from: filtered)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                stepValue(direction: 1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                stepValue(direction: -1)
                return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)):
                control.window?.makeFirstResponder(nil)
                FocusReturnManager.shared.returnFocusToPreviousApp()
                return true
            default:
                return false
            }
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            switch event.keyCode {
            case 126: // Up arrow
                stepValue(direction: 1)
                return true
            case 125: // Down arrow
                stepValue(direction: -1)
                return true
            case 36, 53: // Enter or Esc
                textField?.window?.makeFirstResponder(nil)
                FocusReturnManager.shared.returnFocusToPreviousApp()
                return true
            default:
                return false
            }
        }

        private func stepValue(direction: Double) {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            let step = stepForFlags(flags)
            let current = Double(parent.text) ?? parent.min
            let newValue = clamp(current + (step * direction))
            let formatted = formatValue(newValue)
            parent.text = formatted
            textField?.stringValue = formatted
            applyValue(from: formatted)
        }

        private func applyValue(from text: String) {
            guard let value = Double(text) else { return }
            let clamped = clamp(value)
            parent.onValueChange(clamped)
        }

        private func clamp(_ value: Double) -> Double {
            Swift.min(parent.max, Swift.max(parent.min, value))
        }

        private func stepForFlags(_ flags: NSEvent.ModifierFlags) -> Double {
            if flags.contains(.command), let cmdStep = parent.cmdStep {
                return cmdStep
            }
            if flags.contains(.shift) {
                return parent.shiftStep
            }
            return parent.step
        }

        private func filterText(_ input: String) -> String {
            if parent.allowsDecimal {
                var result = ""
                var hasDot = false
                for ch in input {
                    if ch >= "0" && ch <= "9" {
                        result.append(ch)
                    } else if ch == "." && !hasDot {
                        result.append(ch)
                        hasDot = true
                    }
                }
                return result
            }
            return input.filter { $0 >= "0" && $0 <= "9" }
        }

        private func formatValue(_ value: Double) -> String {
            if parent.allowsDecimal {
                let factor = pow(10.0, Double(parent.decimalPlaces))
                let rounded = (value * factor).rounded() / factor
                let format = "%0.\(parent.decimalPlaces)f"
                var str = String(format: format, rounded)
                while str.contains(".") && (str.hasSuffix("0") || str.hasSuffix(".")) {
                    if str.hasSuffix(".") {
                        str.removeLast()
                        break
                    }
                    str.removeLast()
                }
                return str
            }
            return String(Int(round(value)))
        }
    }
}

final class IncrementingTextField: NSTextField {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
