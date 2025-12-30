//
//  GhosttyApp.swift
//  CodeEdit
//
//  Created with libghostty integration
//

import AppKit
import GhosttyKit

/// Singleton wrapper around ghostty_app_t for CodeEdit terminal integration.
/// This provides the global libghostty app instance that manages all terminal surfaces.
@MainActor
final class GhosttyApp: ObservableObject {

    /// Shared singleton instance
    static let shared = GhosttyApp()

    /// Readiness state of the Ghostty app
    enum Readiness: String {
        case loading
        case error
        case ready
    }

    /// Current readiness state
    @Published private(set) var readiness: Readiness = .loading

    /// The underlying libghostty app instance
    private(set) var app: ghostty_app_t?

    /// The global configuration
    private(set) var config: GhosttyConfig?

    /// Track if ghostty has been globally initialized
    private static var isInitialized = false

    private init() {
        // Initialize libghostty globally (must be done before any other calls)
        if !Self.isInitialized {
            let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
            if result != 0 { // GHOSTTY_SUCCESS = 0
                readiness = .error
                return
            }
            Self.isInitialized = true
        }

        // Load configuration
        guard let config = GhosttyConfig.createDefault() else {
            readiness = .error
            return
        }
        self.config = config

        // Create runtime configuration with callbacks
        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: { userdata in GhosttyApp.wakeup(userdata) },
            action_cb: { app, target, action in
                GhosttyApp.handleAction(app!, target: target, action: action)
            },
            read_clipboard_cb: { userdata, loc, state in
                GhosttyApp.readClipboard(userdata, location: loc, state: state)
            },
            confirm_read_clipboard_cb: nil,
            write_clipboard_cb: { userdata, loc, content, len, confirm in
                GhosttyApp.writeClipboard(
                    userdata,
                    location: loc,
                    content: content,
                    len: len,
                    confirm: confirm
                )
            },
            close_surface_cb: { userdata, processAlive in
                GhosttyApp.closeSurface(userdata, processAlive: processAlive)
            }
        )

        // Create the ghostty app
        guard let app = ghostty_app_new(&runtimeConfig, config.config) else {
            readiness = .error
            return
        }
        self.app = app

        // Set initial focus state
        ghostty_app_set_focus(app, NSApp.isActive)

        // Register for app activation notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        readiness = .ready
    }

    deinit {
        if let app = app {
            ghostty_app_free(app)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - App Operations

    /// Process pending events in the libghostty event loop
    func tick() {
        guard let app = app else { return }
        ghostty_app_tick(app)
    }

    // MARK: - Notifications

    @objc
    private func applicationDidBecomeActive(notification: Notification) {
        guard let app = app else { return }
        ghostty_app_set_focus(app, true)
    }

    @objc
    private func applicationDidResignActive(notification: Notification) {
        guard let app = app else { return }
        ghostty_app_set_focus(app, false)
    }

    // MARK: - Callbacks

    private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            GhosttyApp.shared.tick()
        }
    }

    private static func handleAction(
        _ app: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        // For CodeEdit, we handle a minimal set of actions
        // Most terminal management is handled by CodeEdit's tab/split system
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            return handleSetTitle(target: target, titleAction: action.action.set_title)

        case GHOSTTY_ACTION_PWD:
            return handlePwdChanged(target: target, pwdAction: action.action.pwd)

        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()
            return true

        default:
            // Unhandled action - this is fine, CodeEdit handles most UI actions
            return false
        }
    }

    private static func handleSetTitle(target: ghostty_target_s, titleAction: ghostty_action_set_title_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface,
              let surfaceView = surfaceView(from: surface),
              let title = String(cString: titleAction.title!, encoding: .utf8) else {
            return false
        }

        DispatchQueue.main.async {
            surfaceView.title = title
        }
        return true
    }

    private static func handlePwdChanged(target: ghostty_target_s, pwdAction: ghostty_action_pwd_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface,
              let surfaceView = surfaceView(from: surface),
              let pwd = String(cString: pwdAction.pwd!, encoding: .utf8) else {
            return false
        }

        DispatchQueue.main.async {
            surfaceView.pwd = pwd
        }
        return true
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let surfaceView = surfaceUserdata(from: userdata),
              let surface = surfaceView.surface?.surface else { return }

        let pasteboard = NSPasteboard.general
        let str = pasteboard.string(forType: .string) ?? ""

        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
    }

    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        guard let content = content, len > 0 else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Write the first text/plain content
        for index in 0..<len {
            let item = content[index]
            guard let mimePtr = item.mime,
                  let dataPtr = item.data else { continue }

            let mime = String(cString: mimePtr)
            let contentData = String(cString: dataPtr)

            if mime == "text/plain" {
                pasteboard.setString(contentData, forType: .string)
                break
            }
        }
    }

    private static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
        guard let surfaceView = surfaceUserdata(from: userdata) else { return }
        surfaceView.delegate?.surfaceDidTerminate(surfaceView, exitCode: processAlive ? nil : 0)
    }

    // MARK: - Helper Methods

    private static func surfaceUserdata(from userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        guard let userdata = userdata else { return nil }
        return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func surfaceView(from surface: ghostty_surface_t) -> GhosttySurfaceView? {
        guard let userdata = ghostty_surface_userdata(surface) else { return nil }
        return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }
}
