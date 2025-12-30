//
//  GhosttyConfig.swift
//  CodeEdit
//
//  Created with libghostty integration
//

import Foundation
import GhosttyKit

/// Wrapper around ghostty_config_t for managing terminal configuration.
final class GhosttyConfig {

    /// The underlying libghostty config instance
    let config: ghostty_config_t

    /// Whether the config was successfully loaded
    var loaded: Bool { true }

    private init(config: ghostty_config_t) {
        self.config = config
    }

    deinit {
        ghostty_config_free(config)
    }

    /// Create a default configuration for CodeEdit.
    /// This creates a minimal config without loading Ghostty's default files.
    static func createDefault() -> GhosttyConfig? {
        guard let cfg = ghostty_config_new() else { return nil }

        // Don't load Ghostty's config files - CodeEdit manages its own settings
        // ghostty_config_load_default_files(cfg)

        // Finalize to apply defaults
        ghostty_config_finalize(cfg)

        return GhosttyConfig(config: cfg)
    }

    /// Clone an existing configuration
    static func clone(from other: ghostty_config_t) -> GhosttyConfig? {
        guard let cfg = ghostty_config_clone(other) else { return nil }
        return GhosttyConfig(config: cfg)
    }

    // MARK: - Configuration Properties

    /// Get a string configuration value
    func getString(_ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        let keyLen = UInt(key.utf8.count)

        guard ghostty_config_get(config, &value, key, keyLen),
              let ptr = value else {
            return nil
        }

        return String(cString: ptr)
    }

    /// Get a boolean configuration value
    func getBool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let str = getString(key) else { return defaultValue }
        return str == "true" || str == "1"
    }

    /// RGB color value
    struct RGBColor {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    /// Get a color configuration value
    func getColor(_ key: String) -> RGBColor? {
        var color = ghostty_config_color_s()
        let keyLen = UInt(key.utf8.count)

        guard ghostty_config_get(config, &color, key, keyLen) else {
            return nil
        }

        return RGBColor(red: color.r, green: color.g, blue: color.b)
    }
}
