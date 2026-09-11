import Foundation
import Testing
@testable import VeljaCore

private let chrome = BrowserTarget(bundleIdentifier: "com.google.Chrome")
private let chromeWork = BrowserTarget(bundleIdentifier: "com.google.Chrome", profileDirectory: "Profile 1")
private let safari = BrowserTarget(bundleIdentifier: "com.apple.Safari")
private let slack = "com.tinyspeck.slackmacgap"
private let githubLink = URL(string: "https://github.com/apple/swift")!
private let zoomLink = URL(string: "https://acme.zoom.us/j/85551234567?pwd=abc")!

private func context(
    source: String? = nil,
    fnPressed: Bool = false,
    installedApps: Set<String> = []
) -> LinkRoutingContext {
    LinkRoutingContext(
        sourceAppBundleIdentifier: source,
        isAlternativeBrowserKeyPressed: fnPressed,
        availableBrowserTargets: [chrome, chromeWork, safari],
        installedAppBundleIdentifiers: installedApps
    )
}

struct LinkRouterTests {
    @Test func checksFnKeyThenAppLinksThenRulesThenPrimaryBrowser() {
        let everythingFromSlack = LinkRule(name: "Slack", sourceAppBundleIdentifiers: [slack], action: .openInBrowser(chromeWork))
        let githubRule = LinkRule(name: "GitHub", urlMatchers: [URLMatcher(kind: .domain, pattern: "github.com")], action: .openInBrowser(chrome))
        let settings = VeljaSettings(primaryBrowser: .browser(safari), alternativeBrowser: .browserPicker, rules: [everythingFromSlack, githubRule])

        #expect(LinkRouter.routeIncomingLink(zoomLink, settings: settings, context: context(source: slack, fnPressed: true, installedApps: ["us.zoom.xos"]))
            == .showBrowserPicker(url: zoomLink, reason: .alternativeBrowserKey))
        #expect(LinkRouter.routeIncomingLink(zoomLink, settings: settings, context: context(source: slack, installedApps: ["us.zoom.xos"]))
            == .openInNativeApp(
                appBundleIdentifier: "us.zoom.xos",
                nativeAppURL: URL(string: "zoommtg://acme.zoom.us/join?action=join&confno=85551234567&pwd=abc")!,
                originalURL: zoomLink,
                handler: .zoom
            ))
        #expect(LinkRouter.routeIncomingLink(zoomLink, settings: settings, context: context(source: slack))
            == .openInBrowser(chromeWork, url: zoomLink, reason: .matchedRule(id: everythingFromSlack.id, name: "Slack")))
        #expect(LinkRouter.routeIncomingLink(githubLink, settings: settings, context: context(source: "com.apple.mail"))
            == .openInBrowser(chrome, url: githubLink, reason: .matchedRule(id: githubRule.id, name: "GitHub")))
        let otherLink = URL(string: "https://example.com")!
        #expect(LinkRouter.routeIncomingLink(otherLink, settings: settings, context: context(source: "com.apple.mail"))
            == .openInBrowser(safari, url: otherLink, reason: .primaryBrowser))
    }

    @Test func unavailableBrowserOrProfileShowsPicker() {
        let firefox = BrowserTarget(bundleIdentifier: "org.mozilla.firefox")
        #expect(LinkRouter.routeIncomingLink(githubLink, settings: VeljaSettings(primaryBrowser: .browser(firefox)), context: context())
            == .showBrowserPicker(url: githubLink, reason: .unavailableBrowser(firefox)))

        let deletedProfile = BrowserTarget(bundleIdentifier: "com.google.Chrome", profileDirectory: "Profile 9")
        let rule = LinkRule(name: "Old", urlMatchers: [URLMatcher(kind: .domain, pattern: "github.com")], action: .openInBrowser(deletedProfile))
        #expect(LinkRouter.routeIncomingLink(githubLink, settings: VeljaSettings(rules: [rule]), context: context())
            == .showBrowserPicker(url: githubLink, reason: .unavailableBrowser(deletedProfile)))
    }

    @Test func appLinkClickedInItsOwnAppOpensInBrowser() {
        let settings = VeljaSettings(primaryBrowser: .browser(safari))
        #expect(LinkRouter.routeIncomingLink(zoomLink, settings: settings, context: context(source: "US.ZOOM.XOS", installedApps: ["us.zoom.xos"]))
            == .openInBrowser(safari, url: zoomLink, reason: .primaryBrowser))

        // Any of the handler's apps counts as its own app, not only the one that would open the link.
        let teamsLink = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting/0")!
        #expect(LinkRouter.routeIncomingLink(teamsLink, settings: settings, context: context(source: "com.microsoft.teams", installedApps: ["com.microsoft.teams2"]))
            == .openInBrowser(safari, url: teamsLink, reason: .primaryBrowser))
    }
}

private struct URLMatcherExample: Sendable, CustomTestStringConvertible {
    var kind: URLMatcherKind
    var pattern: String
    var link: String
    var matches: Bool

    var testDescription: String {
        "\(kind) \"\(pattern)\" \(matches ? "matches" : "does not match") \(link)"
    }
}

private let urlMatcherExamples: [URLMatcherExample] = [
    URLMatcherExample(kind: .domain, pattern: "github.com", link: "https://gist.github.com/x", matches: true),
    URLMatcherExample(kind: .domain, pattern: "*.GitHub.com", link: "http://github.com.:8080/", matches: true),
    URLMatcherExample(kind: .domain, pattern: "https://github.com/some/path", link: "https://api.github.com", matches: true),
    URLMatcherExample(kind: .domain, pattern: "github.com", link: "https://github.com.evil.com", matches: false),
    URLMatcherExample(kind: .domain, pattern: "github.com", link: "https://notgithub.com", matches: false),
    URLMatcherExample(kind: .domain, pattern: "bücher.de", link: "https://bücher.de/a", matches: true),
    URLMatcherExample(kind: .domain, pattern: "bücher.de", link: "https://shop.bücher.de/a", matches: true),
    URLMatcherExample(kind: .domain, pattern: "[::1]:8080", link: "http://[::1]:8080/x", matches: true),
    URLMatcherExample(kind: .domain, pattern: "::1", link: "http://[::1]/x", matches: true),
    URLMatcherExample(kind: .prefix, pattern: "github.com/apple", link: "http://www.github.com/apple/swift", matches: true),
    URLMatcherExample(kind: .prefix, pattern: "github.com/apple", link: "https://gist.github.com/apple", matches: false),
    URLMatcherExample(kind: .prefix, pattern: "github.com", link: "https://github.com@evil.com/", matches: false),
    URLMatcherExample(kind: .prefix, pattern: "https://github.com", link: "https://github.com@evil.com/", matches: false),
    URLMatcherExample(kind: .prefix, pattern: "https://github.com/apple", link: "HTTPS://GITHUB.COM/apple", matches: true),
    URLMatcherExample(kind: .prefix, pattern: "https://github.com/apple", link: "http://github.com/apple", matches: false),
    URLMatcherExample(kind: .prefix, pattern: "example.com/a b", link: "https://example.com/a%20b", matches: true),
    URLMatcherExample(kind: .prefix, pattern: "bücher.de/a", link: "https://bücher.de/a/b", matches: true),
    URLMatcherExample(kind: .wildcard, pattern: "*.atlassian.net/browse/*", link: "https://acme.atlassian.net/browse/ABC-1", matches: true),
    URLMatcherExample(kind: .wildcard, pattern: "*.atlassian.net/browse/*", link: "https://acme.atlassian.net/wiki/x", matches: false),
    URLMatcherExample(kind: .wildcard, pattern: "https://docs.google.com/*", link: "https://evil.com/?https://docs.google.com/", matches: false),
    URLMatcherExample(kind: .wildcard, pattern: "example.com/a+b?c=*", link: "https://example.com/aab?c=1", matches: false),
    URLMatcherExample(kind: .regex, pattern: #"/(issues|pull)/\d+$"#, link: "https://github.com/a/b/PULL/12", matches: true),
    URLMatcherExample(kind: .regex, pattern: "([a-z", link: "https://example.com", matches: false),
]

struct URLMatcherTests {
    @Test(arguments: urlMatcherExamples)
    fileprivate func matchesLinks(_ example: URLMatcherExample) {
        #expect(URLMatcher(kind: example.kind, pattern: example.pattern).matchesURL(URL(string: example.link)!) == example.matches)
    }

    @Test(arguments: [
        ("example.com", true),
        ("*.example.com", true),
        ("bücher.de", true),
        ("[::1]:8080", true),
        ("bob@acme.com", false),
        ("foo.*.com", false),
        ("*.*.example.com", false),
        ("not a domain", false),
        ("  ", false),
    ])
    func validatesDomainPatterns(_ pattern: String, _ isValid: Bool) {
        #expect((URLMatcher(kind: .domain, pattern: pattern).patternValidationError == nil) == isValid)
    }
}
