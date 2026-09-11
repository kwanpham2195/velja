import Foundation

/// Facts about an incoming link that the link router needs besides the settings.
public struct LinkRoutingContext: Sendable {
    /// Bundle identifier of the app the link was clicked in, when it could be detected.
    public var sourceAppBundleIdentifier: String?
    /// True when the Fn (Globe) key was held as the link arrived.
    public var isAlternativeBrowserKeyPressed: Bool
    /// Every browser and browser profile that can open links right now. A plain browser is listed
    /// with a `nil` profile; each known Chromium profile is listed separately.
    public var availableBrowserTargets: Set<BrowserTarget>
    /// Bundle identifiers of installed apps. Only the apps named by ``NativeAppLinkHandler`` matter.
    public var installedAppBundleIdentifiers: Set<String>

    public init(
        sourceAppBundleIdentifier: String?,
        isAlternativeBrowserKeyPressed: Bool,
        availableBrowserTargets: Set<BrowserTarget>,
        installedAppBundleIdentifiers: Set<String>
    ) {
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.isAlternativeBrowserKeyPressed = isAlternativeBrowserKeyPressed
        self.availableBrowserTargets = availableBrowserTargets
        self.installedAppBundleIdentifiers = installedAppBundleIdentifiers
    }
}

/// Why the link router made its decision. Shown in the link history.
public enum LinkRoutingReason: Hashable, Sendable {
    case alternativeBrowserKey
    case matchedRule(id: UUID, name: String)
    case primaryBrowser
    /// The configured browser or profile is not installed anymore, so the picker is shown instead.
    case unavailableBrowser(BrowserTarget)
    /// The link was opened with a `velja:open` URL that named a browser or asked for the picker.
    case veljaOpenCommand
}

extension LinkRoutingReason {
    /// Short explanation for the link history, for example "Rule: Work links".
    public var historyDescription: String {
        switch self {
        case .alternativeBrowserKey: "Fn key held"
        case .matchedRule(_, let name): name.isEmpty ? "Rule" : "Rule: \(name)"
        case .primaryBrowser: "Primary browser"
        case .unavailableBrowser: "Configured browser is not installed"
        case .veljaOpenCommand: "velja:open command"
        }
    }
}

/// The link router's answer for one link.
public enum LinkRoutingDecision: Hashable, Sendable {
    case openInBrowser(BrowserTarget, url: URL, reason: LinkRoutingReason)
    /// Open `nativeAppURL` in the desktop app. `originalURL` is the web link, kept so it can still be
    /// opened in a browser if the app fails to open.
    case openInNativeApp(appBundleIdentifier: String, nativeAppURL: URL, originalURL: URL, handler: NativeAppLinkHandler)
    case showBrowserPicker(url: URL, reason: LinkRoutingReason)
}

/// Decides where an incoming link opens. Checks, in order:
/// 1. the Fn (Globe) key, which sends the link to the alternative browser;
/// 2. app links such as Zoom meetings, when the app is installed, the handler is on, and the link
///    was not clicked in that same app (Zoom opening its own web link in a browser must not loop back);
/// 3. rules, top to bottom;
/// 4. the primary browser.
///
/// A browser that is no longer installed falls back to the browser picker.
public enum LinkRouter {
    /// Returns where the link opens. Pure: every fact about the machine comes from `context`.
    public static func routeIncomingLink(_ url: URL, settings: VeljaSettings, context: LinkRoutingContext) -> LinkRoutingDecision {
        if context.isAlternativeBrowserKeyPressed {
            return decision(for: settings.alternativeBrowser, url: url, reason: .alternativeBrowserKey, context: context)
        }

        let sourceAppBundleIdentifier = context.sourceAppBundleIdentifier?.lowercased()
        for handler in NativeAppLinkHandler.allCases where settings.isNativeAppLinkHandlerEnabled(handler) {
            if let sourceAppBundleIdentifier, handler.appBundleIdentifiers.contains(where: { $0.lowercased() == sourceAppBundleIdentifier }) {
                continue
            }
            guard let appBundleIdentifier = handler.appBundleIdentifiers.first(where: context.installedAppBundleIdentifiers.contains),
                  let nativeAppURL = handler.nativeAppURL(for: url) else {
                continue
            }
            return .openInNativeApp(
                appBundleIdentifier: appBundleIdentifier,
                nativeAppURL: nativeAppURL,
                originalURL: url,
                handler: handler
            )
        }

        if let rule = settings.rules.first(where: { $0.matchesLink(url, sourceAppBundleIdentifier: context.sourceAppBundleIdentifier) }) {
            let reason = LinkRoutingReason.matchedRule(id: rule.id, name: rule.name)
            switch rule.action {
            case .openInBrowser(let target):
                return decision(for: .browser(target), url: url, reason: reason, context: context)
            case .showBrowserPicker:
                return .showBrowserPicker(url: url, reason: reason)
            }
        }

        return decision(for: settings.primaryBrowser, url: url, reason: .primaryBrowser, context: context)
    }

    /// Resolves a browser selection, falling back to the picker when the browser or profile is gone.
    static func decision(
        for selection: BrowserSelection,
        url: URL,
        reason: LinkRoutingReason,
        context: LinkRoutingContext
    ) -> LinkRoutingDecision {
        switch selection {
        case .browserPicker:
            return .showBrowserPicker(url: url, reason: reason)
        case .browser(let target):
            guard context.availableBrowserTargets.contains(target) else {
                return .showBrowserPicker(url: url, reason: .unavailableBrowser(target))
            }
            return .openInBrowser(target, url: url, reason: reason)
        }
    }
}
