import Foundation

/// What a matching ``LinkRule`` does with the link.
public enum LinkRuleAction: Hashable, Sendable {
    case openInBrowser(BrowserTarget)
    case showBrowserPicker
}

extension LinkRuleAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case target
    }

    private enum Kind: String, Codable {
        case openInBrowser
        case showBrowserPicker
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .openInBrowser:
            self = .openInBrowser(try container.decode(BrowserTarget.self, forKey: .target))
        case .showBrowserPicker:
            self = .showBrowserPicker
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .openInBrowser(let target):
            try container.encode(Kind.openInBrowser, forKey: .kind)
            try container.encode(target, forKey: .target)
        case .showBrowserPicker:
            try container.encode(Kind.showBrowserPicker, forKey: .kind)
        }
    }
}

/// A user rule that sends matching links to a chosen browser, for example
/// "links from Slack open in the Work Chrome profile".
///
/// A link matches when it satisfies any of the URL matchers (if there are any) and comes from any of
/// the source apps (if there are any). A rule with no usable conditions never matches.
public struct LinkRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var urlMatchers: [URLMatcher]
    /// Bundle identifiers of the apps the link must come from, such as `com.tinyspeck.slackmacgap`.
    public var sourceAppBundleIdentifiers: [String]
    public var action: LinkRuleAction

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        urlMatchers: [URLMatcher] = [],
        sourceAppBundleIdentifiers: [String] = [],
        action: LinkRuleAction
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.urlMatchers = urlMatchers
        self.sourceAppBundleIdentifiers = sourceAppBundleIdentifiers
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case urlMatchers
        case sourceAppBundleIdentifiers
        case action
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        urlMatchers = try container.decodeIfPresent([URLMatcher].self, forKey: .urlMatchers) ?? []
        sourceAppBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .sourceAppBundleIdentifiers) ?? []
        action = try container.decode(LinkRuleAction.self, forKey: .action)
    }

    /// Builds the rule behind "Always Open in …" in the browser picker: links on this link's domain
    /// (ignoring a leading `www.`) open in the chosen browser. Returns `nil` for links without a host.
    public static func makeAlwaysOpenDomainRule(for url: URL, target: BrowserTarget, browserName: String) -> LinkRule? {
        guard var domain = URLMatcher.normalizedHost(of: url) else {
            return nil
        }
        if domain.hasPrefix("www."), domain.count > 4 {
            domain.removeFirst(4)
        }
        return LinkRule(
            name: "Open \(domain) in \(browserName)",
            urlMatchers: [URLMatcher(kind: .domain, pattern: domain)],
            action: .openInBrowser(target)
        )
    }

    /// URL matchers that have a pattern. Blank matchers left over from editing are ignored.
    public var activeURLMatchers: [URLMatcher] {
        urlMatchers.filter { !$0.isBlank }
    }

    /// True when the rule has at least one URL pattern or source app, so it can match something.
    public var hasConditions: Bool {
        !activeURLMatchers.isEmpty || !sourceAppBundleIdentifiers.isEmpty
    }

    /// Returns true when this enabled rule applies to a link opened from the given app.
    public func matchesLink(_ url: URL, sourceAppBundleIdentifier: String?) -> Bool {
        guard isEnabled, hasConditions else {
            return false
        }
        let matchers = activeURLMatchers
        if !matchers.isEmpty, !matchers.contains(where: { $0.matchesURL(url) }) {
            return false
        }
        if !sourceAppBundleIdentifiers.isEmpty {
            guard let sourceAppBundleIdentifier else {
                return false
            }
            let isFromListedApp = sourceAppBundleIdentifiers.contains {
                $0.caseInsensitiveCompare(sourceAppBundleIdentifier) == .orderedSame
            }
            if !isFromListedApp {
                return false
            }
        }
        return true
    }
}
