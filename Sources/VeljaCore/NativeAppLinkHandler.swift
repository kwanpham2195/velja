import Foundation

/// A desktop app that Velja can open certain web links in directly, such as Zoom meeting links in Zoom.
///
/// Each handler only applies when one of its apps is installed and the user has not turned it off.
/// Handlers start on, except those where ``isEnabledByDefault`` is false.
/// The rewrites follow the ones documented in Finicky's configuration wiki.
public enum NativeAppLinkHandler: String, CaseIterable, Codable, Sendable {
    case zoom
    case microsoftTeams
    case figma
    case spotify
    case discord
    case appleMusic

    public var displayName: String {
        switch self {
        case .zoom: "Zoom"
        case .microsoftTeams: "Microsoft Teams"
        case .figma: "Figma"
        case .spotify: "Spotify"
        case .discord: "Discord"
        case .appleMusic: "Apple Music"
        }
    }

    /// Short description of which links the handler takes, shown in settings.
    public var handledLinksDescription: String {
        switch self {
        case .zoom: "Meeting links like zoom.us/j/123456789"
        case .microsoftTeams: "Meeting and chat links on teams.microsoft.com/l/…"
        case .figma: "Files, designs, boards, prototypes, and slides on figma.com"
        case .spotify: "Links on open.spotify.com"
        case .discord: "Channel and message links on discord.com/channels/…"
        case .appleMusic: "Links on music.apple.com"
        }
    }

    /// Bundle identifiers of apps that can open the rewritten link, in order of preference.
    public var appBundleIdentifiers: [String] {
        switch self {
        case .zoom: ["us.zoom.xos"]
        case .microsoftTeams: ["com.microsoft.teams2", "com.microsoft.teams"]
        case .figma: ["com.figma.Desktop"]
        case .spotify: ["com.spotify.client"]
        case .discord: ["com.hnc.Discord"]
        case .appleMusic: ["com.apple.Music"]
        }
    }

    /// False for Apple Music: Music.app ships with macOS, so "only when installed" would never hold it back.
    public var isEnabledByDefault: Bool {
        self != .appleMusic
    }

    /// Returns the link to hand to the desktop app, or `nil` when this handler does not take the link.
    /// Some apps receive the original web link unchanged; others need their own URL scheme.
    public func nativeAppURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = URLMatcher.normalizedHost(of: url) else {
            return nil
        }
        let path = url.path(percentEncoded: true)
        switch self {
        case .zoom:
            return Self.zoomMeetingURL(for: url, host: host, path: path)
        case .microsoftTeams:
            guard host == "teams.microsoft.com", path.hasPrefix("/l/") else {
                return nil
            }
            return Self.replacingScheme(of: url, with: "msteams")
        case .figma:
            guard host == "figma.com" || host == "www.figma.com" else {
                return nil
            }
            let figmaDocumentPaths: Set<String> = ["file", "design", "board", "proto", "slides"]
            let firstPathComponent = path.split(separator: "/").first.map(String.init) ?? ""
            return figmaDocumentPaths.contains(firstPathComponent) ? url : nil
        case .spotify:
            return host == "open.spotify.com" ? url : nil
        case .discord:
            guard host == "discord.com" || host == "www.discord.com", path.hasPrefix("/channels/") else {
                return nil
            }
            return Self.replacingScheme(of: url, with: "discord")
        case .appleMusic:
            guard host == "music.apple.com" || host == "geo.music.apple.com" else {
                return nil
            }
            return Self.replacingScheme(of: url, with: "itmss")
        }
    }

    /// Turns `https://us02web.zoom.us/j/85551234567?pwd=abc` into
    /// `zoommtg://us02web.zoom.us/join?action=join&confno=85551234567&pwd=abc`. Keeps the host, which
    /// selects the account's Zoom cluster, and passes `pwd`, `tk`, and `uname` through still percent-encoded.
    private static func zoomMeetingURL(for url: URL, host: String, path: String) -> URL? {
        guard host == "zoom.us" || host.hasSuffix(".zoom.us") else {
            return nil
        }
        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: true)
        guard pathComponents.count == 2, pathComponents[0] == "j",
              !pathComponents[1].isEmpty, pathComponents[1].allSatisfy(\.isASCII), pathComponents[1].allSatisfy(\.isNumber) else {
            return nil
        }
        var queryItems = [
            URLQueryItem(name: "action", value: "join"),
            URLQueryItem(name: "confno", value: String(pathComponents[1])),
        ]
        let originalQueryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        for passedThroughName in ["pwd", "tk", "uname"] {
            if let value = originalQueryItems.first(where: { $0.name == passedThroughName })?.value, !value.isEmpty {
                queryItems.append(URLQueryItem(name: passedThroughName, value: value))
            }
        }
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = host
        components.path = "/join"
        components.percentEncodedQueryItems = queryItems
        return components.url
    }

    private static func replacingScheme(of url: URL, with scheme: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = scheme
        return components.url
    }
}
