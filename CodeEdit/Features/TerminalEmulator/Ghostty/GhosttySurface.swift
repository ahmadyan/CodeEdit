//
//  GhosttySurface.swift
//  CodeEdit
//
//  Created with libghostty integration
//

import AppKit
import GhosttyKit

/// Wrapper around ghostty_surface_t representing a single terminal instance.
/// Each GhosttySurface corresponds to one terminal session.
@MainActor
final class GhosttySurface {

    /// The underlying libghostty surface
    let surface: ghostty_surface_t

    init?(app: ghostty_app_t, view: NSView, workingDirectory: URL?, command: String? = nil) {
        var config = ghostty_surface_config_new()

        // Configure platform
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()
        config.userdata = Unmanaged.passUnretained(view).toOpaque()

        // Set scale factor (convert CGFloat to Double)
        if let scaleFactor = NSScreen.main?.backingScaleFactor {
            config.scale_factor = Double(scaleFactor)
        } else {
            config.scale_factor = 2.0
        }

        // Create surface with proper string lifetime management
        // Strings must remain valid during ghostty_surface_new call
        let newSurface = Self.createSurfaceWithStrings(
            app: app,
            config: &config,
            workingDirectory: workingDirectory?.path,
            command: command
        )

        guard let surface = newSurface else {
            return nil
        }

        self.surface = surface
    }

    /// Helper to create surface with proper C string lifetime management.
    /// Uses nested withCString closures to ensure pointers remain valid.
    private static func createSurfaceWithStrings(
        app: ghostty_app_t,
        config: inout ghostty_surface_config_s,
        workingDirectory: String?,
        command: String?
    ) -> ghostty_surface_t? {
        // Helper for optional string -> C string conversion with proper lifetime
        func withOptionalCString<T>(
            _ string: String?,
            _ body: (UnsafePointer<CChar>?) -> T
        ) -> T {
            if let string = string {
                return string.withCString { body($0) }
            } else {
                return body(nil)
            }
        }

        // Nest the closures to keep all strings alive during surface creation
        return withOptionalCString(workingDirectory) { pwdPtr in
            withOptionalCString(command) { cmdPtr in
                config.working_directory = pwdPtr
                config.command = cmdPtr
                return ghostty_surface_new(app, &config)
            }
        }
    }

    deinit {
        // Free must happen on main thread
        let surfaceToFree = surface
        Task.detached { @MainActor in
            ghostty_surface_free(surfaceToFree)
        }
    }

    // MARK: - Text Input

    /// Send text to the terminal
    func sendText(_ text: String) {
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    /// Send a key event to the terminal
    func sendKey(_ event: GhosttyInput.KeyEvent) {
        let cEvent = event.cValue
        _ = ghostty_surface_key(surface, cEvent)
    }

    /// Send preedit (IME composition) text
    func sendPreedit(_ text: String?) {
        if let text = text {
            text.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(text.utf8.count))
            }
        } else {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    // MARK: - Mouse Input

    /// Send a mouse button event
    func sendMouseButton(
        action: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e,
        mods: ghostty_input_mods_e
    ) -> Bool {
        ghostty_surface_mouse_button(surface, action, button, mods)
    }

    /// Send mouse position update
    func sendMousePosition(posX: Double, posY: Double, mods: ghostty_input_mods_e) {
        ghostty_surface_mouse_pos(surface, posX, posY, mods)
    }

    /// Send scroll event
    func sendMouseScroll(deltaX: Double, deltaY: Double, mods: ghostty_input_scroll_mods_t) {
        ghostty_surface_mouse_scroll(surface, deltaX, deltaY, mods)
    }

    /// Check if the terminal has captured the mouse
    var isMouseCaptured: Bool {
        ghostty_surface_mouse_captured(surface)
    }

    // MARK: - Surface State

    /// Set the surface size in pixels
    func setSize(width: UInt32, height: UInt32) {
        ghostty_surface_set_size(surface, width, height)
    }

    /// Set the content scale factor (for Retina displays)
    func setContentScale(scaleX: Double, scaleY: Double) {
        ghostty_surface_set_content_scale(surface, scaleX, scaleY)
    }

    /// Set focus state
    func setFocus(_ focused: Bool) {
        ghostty_surface_set_focus(surface, focused)
    }

    /// Set occlusion state (window visibility)
    func setOcclusion(_ occluded: Bool) {
        ghostty_surface_set_occlusion(surface, occluded)
    }

    /// Trigger a draw/render
    func draw() {
        ghostty_surface_draw(surface)
    }

    /// Refresh the surface
    func refresh() {
        ghostty_surface_refresh(surface)
    }

    /// Get the current size information
    var size: ghostty_surface_size_s {
        ghostty_surface_size(surface)
    }

    // MARK: - Selection

    /// Check if there's an active selection
    var hasSelection: Bool {
        ghostty_surface_has_selection(surface)
    }

    /// Read the current selection text
    func readSelection() -> String? {
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text),
              let ptr = text.text else {
            return nil
        }

        let result = String(cString: ptr)
        ghostty_surface_free_text(surface, &text)
        return result
    }

    // MARK: - Actions

    /// Perform a named action (e.g., "copy", "paste", "reset")
    @discardableResult
    func performAction(_ action: String) -> Bool {
        action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    /// Request to close the surface
    func requestClose() {
        ghostty_surface_request_close(surface)
    }

    /// Check if the process has exited
    var processExited: Bool {
        ghostty_surface_process_exited(surface)
    }

    /// Check if closing requires confirmation
    var needsConfirmQuit: Bool {
        ghostty_surface_needs_confirm_quit(surface)
    }

    // MARK: - IME Support

    /// Represents the position and size of the IME composition area
    struct IMEPoint {
        let posX: Double
        let posY: Double
        let width: Double
        let height: Double
    }

    /// Get the IME composition point for input method editors
    func getIMEPoint() -> IMEPoint {
        var posX: Double = 0
        var posY: Double = 0
        var pointWidth: Double = 0
        var pointHeight: Double = 0
        ghostty_surface_ime_point(surface, &posX, &posY, &pointWidth, &pointHeight)
        return IMEPoint(posX: posX, posY: posY, width: pointWidth, height: pointHeight)
    }
}
