import AppKit
import VeljaCore

/// Errors from opening a link in a browser or app.
enum LinkOpenerError: LocalizedError {
    case appNotInstalled(bundleIdentifier: String)

    var errorDescription: String? {
        switch self {
        case .appNotInstalled(let bundleIdentifier):
            "No app with bundle identifier \(bundleIdentifier) is installed."
        }
    }
}

/// Opens links in a specific browser, browser profile, or desktop app.
///
/// Always names the app explicitly. Asking macOS to open a web link with the default browser would
/// hand it straight back to Velja.
@MainActor
enum LinkOpener {
    /// Opens a link in a browser. With a profile, launches the browser with `--profile-directory`,
    /// like `open -na "Google Chrome" --args --profile-directory=…`; a running browser receives the
    /// link from the short-lived new instance.
    static func openLink(_ url: URL, in target: BrowserTarget, inBackground: Bool) async throws {
        let appURL = try installedAppURL(bundleIdentifier: target.bundleIdentifier)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !inBackground
        if !inBackground {
            yieldActivation(toAppWithBundleIdentifier: target.bundleIdentifier)
        }
        if let profileDirectory = target.profileDirectory {
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ChromiumProfileSupport.launchArguments(profileDirectory: profileDirectory, url: url)
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } else {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
    }

    /// Opens a rewritten app link, such as `zoommtg://…`, in the app that handles it.
    static func openLinkInNativeApp(_ url: URL, appBundleIdentifier: String) async throws {
        let appURL = try installedAppURL(bundleIdentifier: appBundleIdentifier)
        let configuration = NSWorkspace.OpenConfiguration()
        yieldActivation(toAppWithBundleIdentifier: appBundleIdentifier)
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }

    /// Launches or brings forward a browser without a link. A profile target opens a window in that profile.
    static func launchBrowser(_ target: BrowserTarget) async throws {
        let appURL = try installedAppURL(bundleIdentifier: target.bundleIdentifier)
        let configuration = NSWorkspace.OpenConfiguration()
        yieldActivation(toAppWithBundleIdentifier: target.bundleIdentifier)
        if let profileDirectory = target.profileDirectory {
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ChromiumProfileSupport.launchArguments(profileDirectory: profileDirectory, url: nil)
        }
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    /// Lets the app come forward under cooperative activation. Yields by bundle identifier because a profile
    /// open goes through a short-lived new instance that is not running yet.
    private static func yieldActivation(toAppWithBundleIdentifier bundleIdentifier: String) {
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleIdentifier)
    }

    private static func installedAppURL(bundleIdentifier: String) throws -> URL {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw LinkOpenerError.appNotInstalled(bundleIdentifier: bundleIdentifier)
        }
        return appURL
    }
}
