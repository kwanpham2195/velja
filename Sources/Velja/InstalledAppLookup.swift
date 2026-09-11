import AppKit

/// Looks up names and icons of installed apps by bundle identifier, for showing source apps in rules.
@MainActor
enum InstalledAppLookup {
    /// The app's Finder name, or the bundle identifier when the app is not installed.
    static func appName(forBundleIdentifier bundleIdentifier: String) -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        return BrowserCatalog.appDisplayName(at: appURL)
    }

    /// The app's icon, or `nil` when the app is not installed.
    static func appIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false))
    }
}
