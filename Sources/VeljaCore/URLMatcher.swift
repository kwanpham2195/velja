import Foundation

/// How a ``URLMatcher`` compares its pattern against a link.
public enum URLMatcherKind: String, Codable, CaseIterable, Sendable {
    /// Matches the host or any of its subdomains. `example.com` matches `docs.example.com`.
    case domain
    /// Matches links that start with the pattern. Case-insensitive.
    case prefix
    /// Matches the whole link against a pattern where `*` stands for any run of characters. Case-insensitive.
    case wildcard
    /// Matches when the regular expression finds a match anywhere in the full link. Case-insensitive.
    case regex
}

/// One URL condition of a ``LinkRule``, such as "the link is on github.com".
///
/// Prefix and wildcard patterns written without a scheme (`github.com/org`) are compared against the
/// link with its scheme and user info removed, and also with a leading `www.` removed. Every prefix
/// and wildcard comparison also tries the percent-decoded link, so `example.com/a b` matches `a%20b`.
public struct URLMatcher: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: URLMatcherKind
    public var pattern: String

    public init(id: UUID = UUID(), kind: URLMatcherKind, pattern: String) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case pattern
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(URLMatcherKind.self, forKey: .kind)
        pattern = try container.decode(String.self, forKey: .pattern)
    }

    /// True when the pattern contains nothing but whitespace. Blank matchers are ignored by rules.
    public var isBlank: Bool {
        pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Explains why the pattern can never match, or `nil` when the pattern is usable.
    public var patternValidationError: String? {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPattern.isEmpty {
            return "Enter a pattern."
        }
        switch kind {
        case .domain:
            if URLMatcher.normalizedDomain(fromPattern: trimmedPattern).isEmpty {
                if trimmedPattern.contains("@") {
                    return "Enter a domain like example.com, not an email address."
                }
                if trimmedPattern.contains("*") {
                    return "Use * only at the start, like *.example.com."
                }
                return "Enter a domain like example.com."
            }
        case .regex:
            if (try? NSRegularExpression(pattern: trimmedPattern, options: [.caseInsensitive])) == nil {
                return "This is not a valid regular expression."
            }
        case .prefix, .wildcard:
            break
        }
        return nil
    }

    /// Returns true when the link satisfies this matcher. Blank or invalid patterns never match.
    public func matchesURL(_ url: URL) -> Bool {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return false
        }
        switch kind {
        case .domain:
            return URLMatcher.hostMatchesDomain(url: url, domainPattern: trimmedPattern)
        case .prefix:
            let comparablePattern = URLMatcher.patternWithPunycodeHost(trimmedPattern.lowercased())
            return URLMatcher.comparableURLStrings(for: url, pattern: trimmedPattern)
                .contains { $0.lowercased().hasPrefix(comparablePattern) }
        case .wildcard:
            let comparablePattern = URLMatcher.patternWithPunycodeHost(trimmedPattern.lowercased())
            guard let expression = URLMatcher.wildcardExpression(fromPattern: comparablePattern) else {
                return false
            }
            return URLMatcher.comparableURLStrings(for: url, pattern: trimmedPattern)
                .contains { expression.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        case .regex:
            guard let expression = try? NSRegularExpression(pattern: trimmedPattern, options: [.caseInsensitive]) else {
                return false
            }
            let urlString = url.absoluteString
            return expression.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil
        }
    }

    /// Turns what a user types into a bare lowercase ASCII host the way link hosts arrive: `*.Example.com`,
    /// `https://example.com/path` and `example.com:8080` become `example.com`, `bücher.de` becomes
    /// `xn--bcher-kva.de`, and `[::1]:8080` becomes `::1`. Returns an empty string for text that can never
    /// match a host, such as `bob@example.com` or `foo.*.com`.
    public static func normalizedDomain(fromPattern pattern: String) -> String {
        var domain = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if domain.contains("://") {
            domain = URL(string: domain)?.host(percentEncoded: false) ?? ""
        }
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }
        domain = hostRemovingPort(domain)
        if domain.hasPrefix("*.") {
            domain.removeFirst(2)
        }
        while domain.hasPrefix(".") {
            domain.removeFirst()
        }
        while domain.hasSuffix(".") {
            domain.removeLast()
        }
        if domain.contains(where: { $0.isWhitespace || $0 == "@" || $0 == "*" }) {
            return ""
        }
        if !domain.allSatisfy(\.isASCII) {
            return URL(string: "https://" + domain)?.host(percentEncoded: false) ?? ""
        }
        return domain
    }

    /// Drops a trailing `:port` and IPv6 brackets. Text with several colons and no brackets is an IPv6
    /// address, so its last group is not a port.
    private static func hostRemovingPort(_ hostAndPort: String) -> String {
        if hostAndPort.hasPrefix("["), let closingBracketIndex = hostAndPort.firstIndex(of: "]") {
            return String(hostAndPort[hostAndPort.index(after: hostAndPort.startIndex)..<closingBracketIndex])
        }
        guard let colonIndex = hostAndPort.firstIndex(of: ":"), colonIndex == hostAndPort.lastIndex(of: ":"),
              hostAndPort[hostAndPort.index(after: colonIndex)...].allSatisfy(\.isNumber) else {
            return hostAndPort
        }
        return String(hostAndPort[..<colonIndex])
    }

    /// Returns the lowercase host of a link without a trailing dot, or `nil` for links without a host.
    public static func normalizedHost(of url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else {
            return nil
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    /// True when the link's host equals the domain or is one of its subdomains.
    public static func hostMatchesDomain(url: URL, domainPattern: String) -> Bool {
        let domain = normalizedDomain(fromPattern: domainPattern)
        guard !domain.isEmpty, let host = normalizedHost(of: url) else {
            return false
        }
        return host == domain || host.hasSuffix("." + domain)
    }

    /// Builds the strings a prefix or wildcard pattern is compared against, each also percent-decoded.
    /// Patterns with a scheme see `scheme://host[:port]/path?query#fragment`; patterns without one see the
    /// same minus `scheme://`, plus that string without a leading `www.`. User info is always left out,
    /// so `https://github.com@evil.com/` does not look like a github.com link.
    private static func comparableURLStrings(for url: URL, pattern: String) -> [String] {
        let candidates: [String]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = components.encodedHost {
            var linkWithoutScheme = host
            if let port = components.port {
                linkWithoutScheme += ":\(port)"
            }
            linkWithoutScheme += components.percentEncodedPath
            if let query = components.percentEncodedQuery {
                linkWithoutScheme += "?" + query
            }
            if let fragment = components.percentEncodedFragment {
                linkWithoutScheme += "#" + fragment
            }
            if pattern.contains("://") {
                candidates = [(components.scheme ?? "") + "://" + linkWithoutScheme]
            } else if linkWithoutScheme.lowercased().hasPrefix("www.") {
                candidates = [linkWithoutScheme, String(linkWithoutScheme.dropFirst(4))]
            } else {
                candidates = [linkWithoutScheme]
            }
        } else {
            candidates = [url.absoluteString]
        }
        let decodedCandidates = candidates.compactMap { candidate in
            candidate.removingPercentEncoding.flatMap { $0 == candidate ? nil : $0 }
        }
        return candidates + decodedCandidates
    }

    /// Converts a non-ASCII host at the start of a pattern without a scheme to punycode, so `bücher.de/a`
    /// compares like the link text `xn--bcher-kva.de/a`. Hosts with `*` or `@` are left as typed.
    private static func patternWithPunycodeHost(_ pattern: String) -> String {
        guard !pattern.contains("://") else {
            return pattern
        }
        let hostEndIndex = pattern.firstIndex(where: { "/?#".contains($0) }) ?? pattern.endIndex
        let hostPart = String(pattern[..<hostEndIndex])
        guard !hostPart.allSatisfy(\.isASCII), !hostPart.contains("*"), !hostPart.contains("@"),
              let hostURL = URL(string: "https://" + hostPart),
              let components = URLComponents(url: hostURL, resolvingAgainstBaseURL: false),
              let punycodeHost = components.encodedHost, !punycodeHost.isEmpty else {
            return pattern
        }
        let port = components.port.map { ":\($0)" } ?? ""
        return punycodeHost + port + String(pattern[hostEndIndex...])
    }

    /// Compiles a wildcard pattern into an anchored, case-insensitive regular expression.
    private static func wildcardExpression(fromPattern pattern: String) -> NSRegularExpression? {
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escapedPattern.replacingOccurrences(of: "\\*", with: ".*") + "$"
        return try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }
}
