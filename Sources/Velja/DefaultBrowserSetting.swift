import AppKit

/// Reads and changes the system's default web browser. Velja only sees links while it is the default browser.
@MainActor
enum DefaultBrowserSetting {
    /// True when Velja opens both http and https links by default.
    static func isVeljaDefaultBrowser() -> Bool {
        guard let ownBundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }
        return ["http", "https"].allSatisfy { scheme in
            guard let probeURL = URL(string: "\(scheme)://example.com"),
                  let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else {
                return false
            }
            return Bundle(url: handlerURL)?.bundleIdentifier == ownBundleIdentifier
        }
    }

    /// Asks macOS to make Velja the default browser. macOS shows a confirmation dialog, and throws when
    /// the user declines.
    static func makeVeljaDefaultBrowser() async throws {
        let ownAppURL = Bundle.main.bundleURL
        try await NSWorkspace.shared.setDefaultApplication(at: ownAppURL, toOpenURLsWithScheme: "http")
        // Confirming the http prompt normally covers https too. Set it explicitly if it did not.
        if !isVeljaDefaultBrowser() {
            try await NSWorkspace.shared.setDefaultApplication(at: ownAppURL, toOpenURLsWithScheme: "https")
        }
    }
}
