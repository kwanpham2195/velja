import Foundation

/// Follows the redirects of a short link and reports where it leads.
public protocol ShortURLRedirectResolving: Sendable {
    /// Returns the first redirect target outside the known shorteners, or `nil` when there is none or the request fails.
    func resolveRedirectDestination(of url: URL) async -> URL?
}

/// Resolves short links with a cookie-less HTTPS HEAD request that gives up after a few seconds.
///
/// Redirects are followed only while they stay on known shorteners. The first redirect that leaves them is
/// recorded and not followed, so the destination site is never contacted. Shorteners that reject HEAD with
/// 405 or 501 are asked once more with GET.
public struct URLSessionShortURLRedirectResolver: ShortURLRedirectResolving {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 3) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
        self.timeout = timeout
    }

    public func resolveRedirectDestination(of url: URL) async -> URL? {
        for httpMethod in ["HEAD", "GET"] {
            var request = URLRequest(url: ShortURLExpander.upgradingToHTTPS(url), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.httpMethod = httpMethod
            let redirectStopper = ShortURLRedirectStopper()
            guard let (_, response) = try? await session.data(for: request, delegate: redirectStopper) else {
                return nil
            }
            if let destination = redirectStopper.destinationURL {
                return destination
            }
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode == 405 || statusCode == 501 else {
                return nil
            }
        }
        return nil
    }
}

/// Per-request redirect policy: follows redirects between known shorteners over HTTPS and records, without
/// following, the first redirect that leaves them.
///
/// `@unchecked Sendable` is safe because the only mutable state, `recordedDestinationURL`, is read and
/// written under `lock`.
final class ShortURLRedirectStopper: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDestinationURL: URL?

    /// The first redirect target outside the known shorteners, once the request has finished.
    var destinationURL: URL? {
        lock.withLock { recordedDestinationURL }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let redirectURL = request.url else {
            completionHandler(nil)
            return
        }
        if ShortURLExpander.isShortURL(redirectURL) {
            var httpsRequest = request
            httpsRequest.url = ShortURLExpander.upgradingToHTTPS(redirectURL)
            completionHandler(httpsRequest)
            return
        }
        lock.withLock { recordedDestinationURL = redirectURL }
        completionHandler(nil)
    }
}

/// Expands links from well-known link shorteners such as bit.ly and t.co, so rules can match the real site.
/// Only the shorteners are contacted; the destination site is never contacted.
public enum ShortURLExpander {
    /// Hosts of link shorteners whose links are expanded.
    static let shortURLHosts: Set<String> = [
        "t.co", "bit.ly", "bitly.com", "tinyurl.com", "ow.ly", "buff.ly", "is.gd", "v.gd", "t.ly",
        "rb.gy", "cutt.ly", "shorturl.at", "tiny.cc", "rebrand.ly", "s.id", "dlvr.it", "trib.al",
        "lnkd.in", "amzn.to", "spoti.fi", "apple.co", "fb.me", "shorturl.gg", "bl.ink", "goo.gl",
    ]

    /// True when the link is an http or https link on a known link shortener.
    public static func isShortURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = URLMatcher.normalizedHost(of: url) else {
            return false
        }
        return shortURLHosts.contains(host)
    }

    /// Swaps `http` for `https`; every listed shortener serves HTTPS, and App Transport Security blocks plain HTTP.
    static func upgradingToHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }

    /// Returns the first link outside the shorteners that a short link redirects to. Links that are not short
    /// links, fail to resolve, or resolve to something other than an http or https link are returned unchanged.
    public static func expandShortURL(_ url: URL, using resolver: any ShortURLRedirectResolving) async -> URL {
        guard isShortURL(url), let destination = await resolver.resolveRedirectDestination(of: url),
              let scheme = destination.scheme?.lowercased(), scheme == "https" || scheme == "http",
              destination.host(percentEncoded: false) != nil else {
            return url
        }
        return destination
    }
}
