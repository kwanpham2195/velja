import Foundation

/// A parsed `linkfork:open` URL, which lets scripts and other apps open a link through Velja.
///
/// Format: `linkfork:open?url=<percent-encoded link>` with optional `prompt` (always show the browser
/// picker; `prompt=false`, `0`, or `no` turn it off), `app=<browser bundle identifier>`, and `profile=<profile directory>`.
/// Only http and https links are accepted, so a web page cannot use this to open local files.
public struct VeljaOpenCommand: Equatable, Sendable {
    public var url: URL
    public var forcesBrowserPicker: Bool
    /// The browser named by `app` and `profile`. The app must still check that it is an installed browser.
    public var browserTarget: BrowserTarget?

    public init(url: URL, forcesBrowserPicker: Bool = false, browserTarget: BrowserTarget? = nil) {
        self.url = url
        self.forcesBrowserPicker = forcesBrowserPicker
        self.browserTarget = browserTarget
    }

    /// The URL scheme Velja registers for these commands.
    public static let urlScheme = "linkfork"

    /// Parses `linkfork:open?…`, `linkfork://open?…`, and `linkfork:///open?…`. Returns `nil` for any other URL,
    /// extra path such as `linkfork://open/extra`, or a missing or non-web `url`.
    public static func parseVeljaOpenCommand(_ commandURL: URL) -> VeljaOpenCommand? {
        guard commandURL.scheme?.lowercased() == urlScheme,
              let components = URLComponents(url: commandURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let commandName: String
        if let host = components.host, !host.isEmpty {
            guard components.path.isEmpty || components.path == "/" else {
                return nil
            }
            commandName = host.lowercased()
        } else {
            commandName = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }
        guard commandName == "open" else {
            return nil
        }
        let queryItems = components.queryItems ?? []
        func queryValue(_ name: String) -> String? {
            queryItems.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let linkText = queryValue("url"), let url = URL(string: linkText),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host(percentEncoded: false)?.isEmpty == false else {
            return nil
        }
        let forcesBrowserPicker = queryItems.contains { item in
            item.name == "prompt" && !["false", "0", "no"].contains(item.value?.lowercased() ?? "")
        }
        var browserTarget: BrowserTarget?
        if let appBundleIdentifier = queryValue("app"), !appBundleIdentifier.isEmpty {
            let profileDirectory = queryValue("profile").flatMap { $0.isEmpty ? nil : $0 }
            browserTarget = BrowserTarget(bundleIdentifier: appBundleIdentifier, profileDirectory: profileDirectory)
        }
        return VeljaOpenCommand(url: url, forcesBrowserPicker: forcesBrowserPicker, browserTarget: browserTarget)
    }
}
