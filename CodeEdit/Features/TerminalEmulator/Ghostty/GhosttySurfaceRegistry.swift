//
//  GhosttySurfaceRegistry.swift
//  CodeEdit
//
//  Tracks Ghostty surface view pointers for safe callback lookup.
//

import Foundation

/// Thread-safe registry for mapping Ghostty userdata pointers to surface views.
final class GhosttySurfaceRegistry {
    static let shared = GhosttySurfaceRegistry()

    private let lock = NSLock()
    private let table = NSMapTable<NSValue, GhosttySurfaceView>(
        keyOptions: .strongMemory,
        valueOptions: .weakMemory
    )
    private weak var activeSurface: GhosttySurfaceView?

    private init() {}

    func register(_ view: GhosttySurfaceView) -> UnsafeMutableRawPointer {
        let pointer = Unmanaged.passUnretained(view).toOpaque()
        lock.lock()
        table.setObject(view, forKey: NSValue(pointer: pointer))
        lock.unlock()
        return pointer
    }

    func unregister(_ view: GhosttySurfaceView) {
        let pointer = Unmanaged.passUnretained(view).toOpaque()
        lock.lock()
        table.removeObject(forKey: NSValue(pointer: pointer))
        if activeSurface === view {
            activeSurface = nil
        }
        lock.unlock()
    }

    func view(for userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        guard let userdata else { return nil }
        lock.lock()
        let view = table.object(forKey: NSValue(pointer: userdata))
        lock.unlock()
        return view
    }

    func setActive(_ view: GhosttySurfaceView?) {
        lock.lock()
        activeSurface = view
        lock.unlock()
    }

    func activeView() -> GhosttySurfaceView? {
        lock.lock()
        let view = activeSurface
        lock.unlock()
        return view
    }
}
