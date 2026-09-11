import AppKit
import VeljaCore

/// An installed app that can open web links, with its Chromium profiles when it has any.
struct InstalledBrowser: Identifiable {
    var bundleIdentifier: String
    var name: String
    var appURL: URL
    var icon: NSImage
    /// Profiles in the browser's own order. Empty for browsers without profile support.
    var profiles: [BrowserProfile]

    var id: String { bundleIdentifier }
}

/// One entry that can be chosen in the browser picker or in settings: a browser, or one of its profiles.
struct BrowserChoice: Identifiable {
    var target: BrowserTarget
    var browserName: String
    var profileName: String?
    var icon: NSImage

    var id: BrowserTarget { target }

    /// "Google Chrome" or "Google Chrome — Work".
    var title: String {
        guard let profileName else {
            return browserName
        }
        return "\(browserName) — \(profileName)"
    }
}

/// Finds the browsers installed on this Mac by asking Launch Services which apps open https links.
enum BrowserCatalog {
    /// Returns installed browsers sorted by name, leaving out Velja itself.
    @MainActor
    static func findInstalledBrowsers() -> [InstalledBrowser] {
        let workspace = NSWorkspace.shared
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let probeURL = URL(string: "https://example.com") else {
            return []
        }

        var browsersByBundleIdentifier: [String: InstalledBrowser] = [:]
        for candidateURL in workspace.urlsForApplications(toOpen: probeURL) {
            guard let bundleIdentifier = Bundle(url: candidateURL)?.bundleIdentifier,
                  bundleIdentifier != ownBundleIdentifier,
                  browsersByBundleIdentifier[bundleIdentifier] == nil,
                  !candidateURL.path(percentEncoded: false).contains("/.Trash/") else {
                continue
            }
            // When several copies are installed, use the one Launch Services prefers.
            let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) ?? candidateURL
            browsersByBundleIdentifier[bundleIdentifier] = InstalledBrowser(
                bundleIdentifier: bundleIdentifier,
                name: appDisplayName(at: appURL),
                appURL: appURL,
                icon: workspace.icon(forFile: appURL.path(percentEncoded: false)),
                profiles: readChromiumProfiles(bundleIdentifier: bundleIdentifier, applicationSupportDirectory: applicationSupportDirectory)
            )
        }
        return browsersByBundleIdentifier.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The name Finder shows for an app, without the `.app` extension.
    static func appDisplayName(at appURL: URL) -> String {
        let displayName = FileManager.default.displayName(atPath: appURL.path(percentEncoded: false))
        return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }

    /// Extra Chromium-style browsers from `VELJA_CHROMIUM_USER_DATA_DIRECTORIES` (`bundle.id=/absolute/path;…`),
    /// used by end-to-end tests to give a fake browser profiles, and for advanced use.
    private static let chromiumUserDataDirectoryOverrides = ChromiumProfileSupport.parseUserDataDirectoryOverrides(
        ProcessInfo.processInfo.environment["VELJA_CHROMIUM_USER_DATA_DIRECTORIES"] ?? ""
    )

    private static func readChromiumProfiles(bundleIdentifier: String, applicationSupportDirectory: URL) -> [BrowserProfile] {
        guard let localStateURL = ChromiumProfileSupport.localStateFileURL(
            forBrowserBundleIdentifier: bundleIdentifier,
            applicationSupportDirectory: applicationSupportDirectory,
            userDataDirectoryOverrides: chromiumUserDataDirectoryOverrides
        ), let localStateData = try? Data(contentsOf: localStateURL) else {
            return []
        }
        return ChromiumProfileSupport.parseLocalStateProfiles(localStateData)
    }
}
