import Foundation

/// Identifies a browser, and optionally one of its profiles, that a link can be opened in.
public struct BrowserTarget: Codable, Hashable, Sendable {
    /// Bundle identifier of the browser app, for example `com.google.Chrome`.
    public var bundleIdentifier: String
    /// Chromium profile directory name such as `Default` or `Profile 1`.
    /// `nil` opens the link in whichever profile the browser uses by default.
    public var profileDirectory: String?

    public init(bundleIdentifier: String, profileDirectory: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.profileDirectory = profileDirectory
    }
}

/// Where a link goes when no more specific setting applies: the browser picker or one fixed browser.
public enum BrowserSelection: Hashable, Sendable {
    case browserPicker
    case browser(BrowserTarget)
}

extension BrowserSelection: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case target
    }

    private enum Kind: String, Codable {
        case browserPicker
        case browser
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .browserPicker:
            self = .browserPicker
        case .browser:
            self = .browser(try container.decode(BrowserTarget.self, forKey: .target))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .browserPicker:
            try container.encode(Kind.browserPicker, forKey: .kind)
        case .browser(let target):
            try container.encode(Kind.browser, forKey: .kind)
            try container.encode(target, forKey: .target)
        }
    }
}
