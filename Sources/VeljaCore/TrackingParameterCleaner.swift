import Foundation

/// Removes tracking parameters such as `utm_source` and `fbclid` from web links before they are opened.
///
/// Only query parameters are touched, and only on http and https links. Links with nothing to
/// remove are returned unchanged, byte for byte.
public enum TrackingParameterCleaner {
    /// Parameter names removed on every site. Compared case-insensitively. Subscriber identifiers such as
    /// `mkt_tok` and `ck_subscriber_id` are kept because unsubscribe and preference pages need them.
    static let trackingParameterNames: Set<String> = [
        // Ad click identifiers
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "twclid", "ttclid",
        "li_fat_id", "yclid", "rb_clickid", "srsltid", "epik", "irclickid", "wickedid",
        // Email and marketing automation
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking",
        "vero_id", "vero_conv", "oly_anon_id", "oly_enc_id", "_openstat", "s_cid",
        // Google Analytics cross-domain linkers
        "_ga", "_gl",
        // Instagram share identifiers
        "igshid", "igsh",
        // Piwik campaign parameters
        "pk_campaign", "pk_kwd", "pk_keyword", "pk_source", "pk_medium", "pk_content", "pk_cid",
        // Hootsuite campaign parameters
        "hmb_campaign", "hmb_medium", "hmb_source",
    ]

    /// Parameter name prefixes removed on every site: Google UTM and Matomo campaign parameters.
    static let trackingParameterPrefixes: [String] = ["utm_", "mtm_"]

    /// Site-specific parameters. Keys are domains; each also covers its subdomains.
    static let siteTrackingParameterNames: [String: Set<String>] = [
        "x.com": ["s", "t", "ref_src", "ref_url"],
        "twitter.com": ["s", "t", "ref_src", "ref_url"],
        "youtube.com": ["si", "feature"],
        "youtu.be": ["si", "feature"],
        "open.spotify.com": ["si"],
        "facebook.com": ["mibextid", "__tn__", "sfnsn", "rdid", "share_url"],
        "tiktok.com": ["_t", "_r", "is_from_webapp", "sender_device", "is_copy_url", "share_app_id", "share_link_id", "u_code"],
        "linkedin.com": ["trk", "trackingid", "lipi", "midtoken", "midsig", "trkemail", "refid"],
        "reddit.com": ["share_id"],
    ]

    /// Site-specific parameter name prefixes, for parameters like Facebook's `__cft__[0]`.
    static let siteTrackingParameterPrefixes: [String: [String]] = [
        "facebook.com": ["__cft__"],
    ]

    /// Returns the link without known tracking parameters. The fragment and all other parameters are kept;
    /// empty items such as a trailing `&` are dropped only when a tracking parameter was removed.
    public static func removeTrackingParameters(from url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.percentEncodedQueryItems, !queryItems.isEmpty else {
            return url
        }
        let host = URLMatcher.normalizedHost(of: url)
        let untrackedItems = queryItems.filter { !isTrackingParameter(named: $0.name, host: host) }
        guard untrackedItems.count != queryItems.count else {
            return url
        }
        let keptItems = untrackedItems.filter { !$0.name.isEmpty || !($0.value ?? "").isEmpty }
        components.percentEncodedQueryItems = keptItems.isEmpty ? nil : keptItems
        return components.url ?? url
    }

    /// True when a query parameter with this percent-encoded name is tracking on the given host.
    static func isTrackingParameter(named percentEncodedName: String, host: String?) -> Bool {
        let name = (percentEncodedName.removingPercentEncoding ?? percentEncodedName).lowercased()
        if trackingParameterNames.contains(name) || trackingParameterPrefixes.contains(where: { name.hasPrefix($0) }) {
            return true
        }
        guard let host else {
            return false
        }
        for (domain, names) in siteTrackingParameterNames where host == domain || host.hasSuffix("." + domain) {
            if names.contains(name) {
                return true
            }
        }
        for (domain, prefixes) in siteTrackingParameterPrefixes where host == domain || host.hasSuffix("." + domain) {
            if prefixes.contains(where: { name.hasPrefix($0) }) {
                return true
            }
        }
        return false
    }
}
