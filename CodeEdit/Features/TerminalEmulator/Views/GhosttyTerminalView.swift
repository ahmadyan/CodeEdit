//
//  GhosttyTerminalView.swift
//  CodeEdit
//
//  SwiftUI wrapper for the Ghostty terminal backend.
//

import SwiftUI
import GhosttyKit

/// SwiftUI view that wraps a GhosttySurfaceView for use in CodeEdit.
/// This provides GPU-accelerated terminal rendering via libghostty.
struct GhosttyTerminalView: NSViewRepresentable {

    /// Working directory URL
    let url: URL

    /// Terminal identifier for caching
    let terminalID: UUID

    /// Callback for title changes
    var onTitleChange: ((String) -> Void)?

    @Environment(\.colorScheme)
    private var colorScheme

    init(
        url: URL,
        terminalID: UUID = UUID(),
        onTitleChange: ((String) -> Void)? = nil
    ) {
        self.url = url
        self.terminalID = terminalID
        self.onTitleChange = onTitleChange
    }

    func makeNSView(context: Context) -> GhosttySurfaceView {
        // Check if GhosttyApp is ready
        guard GhosttyApp.shared.readiness == .ready else {
            // Return an empty view if Ghostty isn't initialized
            return GhosttySurfaceView(workingDirectory: nil, id: terminalID)
        }

        let view = GhosttySurfaceView(
            workingDirectory: url,
            id: terminalID
        )
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {
        // Update color scheme
        let scheme: ghostty_color_scheme_e = colorScheme == .dark
            ? GHOSTTY_COLOR_SCHEME_DARK
            : GHOSTTY_COLOR_SCHEME_LIGHT

        if let app = GhosttyApp.shared.app {
            ghostty_app_set_color_scheme(app, scheme)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitleChange: onTitleChange)
    }

    class Coordinator: GhosttySurfaceViewDelegate {
        var onTitleChange: ((String) -> Void)?

        init(onTitleChange: ((String) -> Void)?) {
            self.onTitleChange = onTitleChange
        }

        func surfaceDidChangeTitle(_ view: GhosttySurfaceView, title: String) {
            onTitleChange?(title)
        }

        func surfaceDidChangePwd(_ view: GhosttySurfaceView, pwd: String?) {
            // Could be used for future features
        }

        func surfaceDidTerminate(_ view: GhosttySurfaceView, exitCode: Int32?) {
            // Handle terminal exit - could show exit message
        }
    }
}

// MARK: - Preview

#if DEBUG
struct GhosttyTerminalView_Previews: PreviewProvider {
    static var previews: some View {
        GhosttyTerminalView(url: URL(filePath: NSHomeDirectory()))
            .frame(width: 800, height: 600)
    }
}
#endif
