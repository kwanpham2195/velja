import Foundation

/// Turns text from the clipboard or a system service into web links.
public enum LinkTextParser {
    /// Returns an http or https link from text such as `https://example.com` or `example.com/page`.
    /// Text without a scheme gets `https://` when it looks like a host name and has no `@`, so email
    /// addresses are not mistaken for links. Anything else returns `nil`.
    public static func webLink(fromText text: String) -> URL? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !trimmedText.contains(where: \.isWhitespace) else {
            return nil
        }
        if let url = URL(string: trimmedText), let scheme = url.scheme?.lowercased() {
            if (scheme == "https" || scheme == "http"), url.host(percentEncoded: false)?.isEmpty == false {
                return url
            }
            // `example.com:8080/path` parses with scheme `example.com`; only reject real schemes here.
            if !scheme.contains(".") {
                return nil
            }
        }
        guard !trimmedText.contains("@"),
              let url = URL(string: "https://" + trimmedText),
              let host = url.host(percentEncoded: false),
              host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return nil
        }
        return url
    }

    /// Extracts web links from free text such as a Services-menu selection, in order and without duplicates.
    /// Links written without a scheme get `https://`, matching ``webLink(fromText:)``.
    public static func webLinks(inText text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var seenLinks = Set<URL>()
        var links: [URL] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard var url = match.url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  let matchedRange = Range(match.range, in: text) else {
                continue
            }
            // The detector adds `http://` to text like `example.com/page`; upgrade only links it gave a scheme.
            if !text[matchedRange].lowercased().hasPrefix(scheme + ":"),
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = "https"
                url = components.url ?? url
            }
            if seenLinks.insert(url).inserted {
                links.append(url)
            }
        }
        return links
    }
}
