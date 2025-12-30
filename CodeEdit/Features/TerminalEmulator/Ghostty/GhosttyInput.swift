//
//  GhosttyInput.swift
//  CodeEdit
//
//  Created with libghostty integration
//

import AppKit
import GhosttyKit

/// Input event structures and helpers for libghostty integration.
enum GhosttyInput {

    /// Key event structure
    struct KeyEvent {
        let action: ghostty_input_action_e
        let mods: ghostty_input_mods_e
        let keycode: UInt32
        let text: String?
        let composing: Bool

        init(
            action: ghostty_input_action_e,
            mods: ghostty_input_mods_e,
            keycode: UInt32,
            text: String? = nil,
            composing: Bool = false
        ) {
            self.action = action
            self.mods = mods
            self.keycode = keycode
            self.text = text
            self.composing = composing
        }

        /// Convert to C structure for libghostty
        var cValue: ghostty_input_key_s {
            var event = ghostty_input_key_s()
            event.action = action
            event.mods = mods
            event.consumed_mods = GHOSTTY_MODS_NONE
            event.keycode = keycode
            event.composing = composing

            // Note: text pointer must remain valid during the call
            // The caller is responsible for using withCString
            return event
        }
    }

    /// Convert NSEvent modifier flags to libghostty modifiers
    static func mods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue

        if flags.contains(.shift) {
            mods |= GHOSTTY_MODS_SHIFT.rawValue
        }
        if flags.contains(.control) {
            mods |= GHOSTTY_MODS_CTRL.rawValue
        }
        if flags.contains(.option) {
            mods |= GHOSTTY_MODS_ALT.rawValue
        }
        if flags.contains(.command) {
            mods |= GHOSTTY_MODS_SUPER.rawValue
        }
        if flags.contains(.capsLock) {
            mods |= GHOSTTY_MODS_CAPS.rawValue
        }
        if flags.contains(.numericPad) {
            mods |= GHOSTTY_MODS_NUM.rawValue
        }

        return ghostty_input_mods_e(rawValue: mods)
    }

    /// Convert macOS keycode to libghostty key
    static func ghosttyKey(from keyCode: UInt16) -> ghostty_input_key_e {
        return keyCodeMap[keyCode] ?? GHOSTTY_KEY_UNIDENTIFIED
    }

    /// Map of macOS keycodes to Ghostty key codes
    /// This is a subset - full mapping would need all 170+ keys
    private static let keyCodeMap: [UInt16: ghostty_input_key_e] = [
        // Letters (A-Z)
        0: GHOSTTY_KEY_A, 11: GHOSTTY_KEY_B, 8: GHOSTTY_KEY_C, 2: GHOSTTY_KEY_D,
        14: GHOSTTY_KEY_E, 3: GHOSTTY_KEY_F, 5: GHOSTTY_KEY_G, 4: GHOSTTY_KEY_H,
        34: GHOSTTY_KEY_I, 38: GHOSTTY_KEY_J, 40: GHOSTTY_KEY_K, 37: GHOSTTY_KEY_L,
        46: GHOSTTY_KEY_M, 45: GHOSTTY_KEY_N, 31: GHOSTTY_KEY_O, 35: GHOSTTY_KEY_P,
        12: GHOSTTY_KEY_Q, 15: GHOSTTY_KEY_R, 1: GHOSTTY_KEY_S, 17: GHOSTTY_KEY_T,
        32: GHOSTTY_KEY_U, 9: GHOSTTY_KEY_V, 13: GHOSTTY_KEY_W, 7: GHOSTTY_KEY_X,
        16: GHOSTTY_KEY_Y, 6: GHOSTTY_KEY_Z,
        // Numbers (GHOSTTY_KEY_DIGIT_x)
        29: GHOSTTY_KEY_DIGIT_0, 18: GHOSTTY_KEY_DIGIT_1, 19: GHOSTTY_KEY_DIGIT_2,
        20: GHOSTTY_KEY_DIGIT_3, 21: GHOSTTY_KEY_DIGIT_4, 23: GHOSTTY_KEY_DIGIT_5,
        22: GHOSTTY_KEY_DIGIT_6, 26: GHOSTTY_KEY_DIGIT_7, 28: GHOSTTY_KEY_DIGIT_8,
        25: GHOSTTY_KEY_DIGIT_9,
        // Function keys
        122: GHOSTTY_KEY_F1, 120: GHOSTTY_KEY_F2, 99: GHOSTTY_KEY_F3, 118: GHOSTTY_KEY_F4,
        96: GHOSTTY_KEY_F5, 97: GHOSTTY_KEY_F6, 98: GHOSTTY_KEY_F7, 100: GHOSTTY_KEY_F8,
        101: GHOSTTY_KEY_F9, 109: GHOSTTY_KEY_F10, 103: GHOSTTY_KEY_F11, 111: GHOSTTY_KEY_F12,
        // Special keys
        36: GHOSTTY_KEY_ENTER, 48: GHOSTTY_KEY_TAB, 49: GHOSTTY_KEY_SPACE,
        51: GHOSTTY_KEY_BACKSPACE, 53: GHOSTTY_KEY_ESCAPE, 117: GHOSTTY_KEY_DELETE,
        115: GHOSTTY_KEY_HOME, 119: GHOSTTY_KEY_END, 116: GHOSTTY_KEY_PAGE_UP,
        121: GHOSTTY_KEY_PAGE_DOWN,
        // Arrow keys (GHOSTTY_KEY_ARROW_x)
        123: GHOSTTY_KEY_ARROW_LEFT, 124: GHOSTTY_KEY_ARROW_RIGHT,
        125: GHOSTTY_KEY_ARROW_DOWN, 126: GHOSTTY_KEY_ARROW_UP,
        // Punctuation (note: BRACKET_LEFT, BRACKET_RIGHT, QUOTE, BACKQUOTE)
        27: GHOSTTY_KEY_MINUS, 24: GHOSTTY_KEY_EQUAL, 33: GHOSTTY_KEY_BRACKET_LEFT,
        30: GHOSTTY_KEY_BRACKET_RIGHT, 42: GHOSTTY_KEY_BACKSLASH, 41: GHOSTTY_KEY_SEMICOLON,
        39: GHOSTTY_KEY_QUOTE, 50: GHOSTTY_KEY_BACKQUOTE, 43: GHOSTTY_KEY_COMMA,
        47: GHOSTTY_KEY_PERIOD, 44: GHOSTTY_KEY_SLASH
    ]

    /// Mouse button event
    struct MouseButtonEvent {
        let action: ghostty_input_mouse_state_e
        let button: ghostty_input_mouse_button_e
        let mods: ghostty_input_mods_e
    }

    /// Mouse position event
    struct MousePosEvent {
        let posX: Double
        let posY: Double
        let mods: ghostty_input_mods_e
    }

    /// Mouse scroll event
    struct MouseScrollEvent {
        let deltaX: Double
        let deltaY: Double
        let mods: ghostty_input_scroll_mods_t

        /// Create a scroll event
        /// - Parameters:
        ///   - deltaX: Horizontal scroll delta
        ///   - deltaY: Vertical scroll delta
        ///   - precision: Whether this is a precision scroll (trackpad)
        init(deltaX: Double, deltaY: Double, precision: Bool = false) {
            self.deltaX = deltaX
            self.deltaY = deltaY
            // ghostty_input_scroll_mods_t is an Int32 type alias
            // The precision flag is typically encoded in the value
            self.mods = precision ? 1 : 0
        }
    }

    /// Convert NSEvent button number to ghostty button
    static func mouseButton(from event: NSEvent) -> ghostty_input_mouse_button_e {
        switch event.buttonNumber {
        case 0: return GHOSTTY_MOUSE_LEFT
        case 1: return GHOSTTY_MOUSE_RIGHT
        case 2: return GHOSTTY_MOUSE_MIDDLE
        default: return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    /// Convert NSEvent phase to momentum
    static func momentum(from phase: NSEvent.Phase) -> ghostty_input_mouse_momentum_e {
        switch phase {
        case .began: return GHOSTTY_MOUSE_MOMENTUM_BEGAN
        case .stationary: return GHOSTTY_MOUSE_MOMENTUM_STATIONARY
        case .changed: return GHOSTTY_MOUSE_MOMENTUM_CHANGED
        case .ended: return GHOSTTY_MOUSE_MOMENTUM_ENDED
        case .cancelled: return GHOSTTY_MOUSE_MOMENTUM_CANCELLED
        case .mayBegin: return GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
        default: return GHOSTTY_MOUSE_MOMENTUM_NONE
        }
    }
}
