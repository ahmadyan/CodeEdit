//
//  GhosttySurfaceView.swift
//  CodeEdit
//
//  Created with libghostty integration
//

// swiftlint:disable file_length

import AppKit
import Combine
import GhosttyKit

/// Protocol for GhosttySurfaceView delegate callbacks
protocol GhosttySurfaceViewDelegate: AnyObject {
    func surfaceDidChangeTitle(_ view: GhosttySurfaceView, title: String)
    func surfaceDidChangePwd(_ view: GhosttySurfaceView, pwd: String?)
    func surfaceDidTerminate(_ view: GhosttySurfaceView, exitCode: Int32?)
}

/// NSView subclass that hosts a libghostty terminal surface.
/// This view handles rendering and input for the terminal.
class GhosttySurfaceView: NSView, ObservableObject {

    /// Unique identifier for this terminal view
    let id: UUID

    /// The underlying Ghostty surface
    private(set) var surface: GhosttySurface?

    /// Delegate for terminal events
    weak var delegate: GhosttySurfaceViewDelegate?

    /// Published properties for SwiftUI binding
    @Published var title: String = "Terminal" {
        didSet {
            delegate?.surfaceDidChangeTitle(self, title: title)
        }
    }

    @Published var pwd: String? {
        didSet {
            delegate?.surfaceDidChangePwd(self, pwd: pwd)
        }
    }

    @Published var cellSize: NSSize = .zero

    /// For IME (Input Method Editor) support
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?

    /// Tracking area for mouse events
    private var trackingArea: NSTrackingArea?

    // MARK: - Initialization

    init(workingDirectory: URL? = nil, id: UUID = UUID()) {
        self.id = id
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Enable layer-backed view for Metal rendering
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        // Create surface
        guard let app = GhosttyApp.shared.app else {
            return
        }

        // Get user's default shell from environment, fallback to /bin/zsh
        // Using the login shell flag (-l) for proper environment setup
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let command = "\(shell) -l"

        self.surface = GhosttySurface(
            app: app,
            view: self,
            workingDirectory: workingDirectory,
            command: command
        )

        // Setup tracking area for mouse events
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
    }

    // MARK: - View Lifecycle

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentScale()
    }

    private func updateContentScale() {
        guard let surface = surface, let window = window else { return }

        let scale = window.backingScaleFactor
        surface.setContentScale(scaleX: scale, scaleY: scale)

        let size = convertToBacking(bounds.size)
        surface.setSize(width: UInt32(size.width), height: UInt32(size.height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        guard let surface = surface else { return }
        let size = convertToBacking(newSize)
        surface.setSize(width: UInt32(size.width), height: UInt32(size.height))
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        surface?.setFocus(true)
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        surface?.setFocus(false)
        return super.resignFirstResponder()
    }

    // MARK: - Tracking Area

    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )

        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        setupTrackingArea()
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface = surface else { return }

        let mods = GhosttyInput.mods(from: event.modifierFlags)

        // Handle text input
        if let text = event.characters, !text.isEmpty {
            // For simple key presses, send as text
            let keyEvent = GhosttyInput.KeyEvent(
                action: GHOSTTY_ACTION_PRESS,
                mods: mods,
                keycode: UInt32(event.keyCode),
                text: text
            )

            // Send key event with text
            text.withCString { ptr in
                var cEvent = keyEvent.cValue
                cEvent.text = ptr
                _ = ghostty_surface_key(surface.surface, cEvent)
            }
        } else {
            // No text, just send the key event
            let keyEvent = GhosttyInput.KeyEvent(
                action: GHOSTTY_ACTION_PRESS,
                mods: mods,
                keycode: UInt32(event.keyCode)
            )
            surface.sendKey(keyEvent)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface = surface else { return }

        let keyEvent = GhosttyInput.KeyEvent(
            action: GHOSTTY_ACTION_RELEASE,
            mods: GhosttyInput.mods(from: event.modifierFlags),
            keycode: UInt32(event.keyCode)
        )
        surface.sendKey(keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        // Handle modifier key changes if needed
        // For now, we just track the modifiers in keyDown/keyUp
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard let surface = surface else { return }
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        _ = surface.sendMouseButton(action: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT, mods: mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface = surface else { return }
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        _ = surface.sendMouseButton(action: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT, mods: mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface = surface else { return }
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        _ = surface.sendMouseButton(action: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT, mods: mods)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface = surface else { return }
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        _ = surface.sendMouseButton(action: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT, mods: mods)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface = surface else { return }
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        let button = GhosttyInput.mouseButton(from: event)
        _ = surface.sendMouseButton(action: GHOSTTY_MOUSE_PRESS, button: button, mods: mods)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface = surface else { return }
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        let button = GhosttyInput.mouseButton(from: event)
        _ = surface.sendMouseButton(action: GHOSTTY_MOUSE_RELEASE, button: button, mods: mods)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface = surface else { return }

        let pos = convert(event.locationInWindow, from: nil)
        // Convert from AppKit coordinates (bottom-left origin) to Ghostty (top-left)
        let mouseY = bounds.height - pos.y
        let mods = GhosttyInput.mods(from: event.modifierFlags)

        surface.sendMousePosition(posX: pos.x, posY: mouseY, mods: mods)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = surface else { return }

        var deltaX = event.scrollingDeltaX
        var deltaY = event.scrollingDeltaY

        // Increase sensitivity for precise scrolling (trackpad)
        if event.hasPreciseScrollingDeltas {
            deltaX *= 2
            deltaY *= 2
        }

        let scrollEvent = GhosttyInput.MouseScrollEvent(
            deltaX: deltaX,
            deltaY: deltaY,
            precision: event.hasPreciseScrollingDeltas
        )

        surface.sendMouseScroll(deltaX: scrollEvent.deltaX, deltaY: scrollEvent.deltaY, mods: scrollEvent.mods)
    }

    // MARK: - Copy/Paste

    /// Copy the current selection to the clipboard
    @objc
    func performCopy(_ sender: Any?) {
        guard let surface = surface, surface.hasSelection,
              let text = surface.readSelection() else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Paste from clipboard to terminal
    @objc
    func performPaste(_ sender: Any?) {
        guard let surface = surface else { return }

        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }

        surface.sendText(text)
    }

    /// Select all terminal content
    @objc
    func performSelectAll(_ sender: Any?) {
        surface?.performAction("select_all")
    }
}

// MARK: - NSMenuItemValidation

extension GhosttySurfaceView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(performCopy(_:)):
            return surface?.hasSelection ?? false
        case #selector(performPaste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        default:
            return true
        }
    }
}

// MARK: - NSTextInputClient

extension GhosttySurfaceView: NSTextInputClient {

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface = surface else { return }

        let text: String
        switch string {
        case let str as String:
            text = str
        case let attrString as NSAttributedString:
            text = attrString.string
        default:
            return
        }

        // Clear any marked text
        markedText.setAttributedString(NSAttributedString())
        surface.sendPreedit(nil)

        // If we're in keyDown, accumulate for later
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
        } else {
            surface.sendText(text)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attrString as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: attrString)
        case let str as String:
            markedText = NSMutableAttributedString(string: str)
        default:
            return
        }

        // Send preedit to terminal
        if markedText.length > 0 {
            surface?.sendPreedit(markedText.string)
        } else {
            surface?.sendPreedit(nil)
        }
    }

    func unmarkText() {
        markedText.setAttributedString(NSAttributedString())
        surface?.sendPreedit(nil)
    }

    func selectedRange() -> NSRange {
        return NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.length)
    }

    func hasMarkedText() -> Bool {
        return markedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface = surface else { return .zero }

        let imePoint = surface.getIMEPoint()
        var rect = NSRect(x: imePoint.posX, y: imePoint.posY, width: imePoint.width, height: imePoint.height)

        // Convert to screen coordinates
        rect = convert(rect, to: nil)
        rect = window?.convertToScreen(rect) ?? rect

        return rect
    }

    func characterIndex(for point: NSPoint) -> Int {
        return 0
    }
}
