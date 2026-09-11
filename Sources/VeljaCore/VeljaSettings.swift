import Foundation

/// Every user setting Velja persists, stored as JSON in `~/Library/Application Support/Velja/Settings.json`.
///
/// Decoding fills in defaults for missing keys, so settings files written by older versions keep loading.
public struct VeljaSettings: Codable, Equatable, Sendable {
    /// Where links go when no rule or app link applies.
    public var primaryBrowser: BrowserSelection
    /// Where links go while the Fn (Globe) key is held. Holding Fn skips rules and app links.
    public var alternativeBrowser: BrowserSelection
    /// Checked in order; the first matching enabled rule wins.
    public var rules: [LinkRule]
    /// Raw values of ``NativeAppLinkHandler`` cases that are off. Stored as strings so unknown values
    /// from newer versions do not break loading. Defaults to the handlers that are not ``NativeAppLinkHandler/isEnabledByDefault``.
    public var disabledNativeAppLinkHandlers: Set<String>
    public var removesTrackingParameters: Bool
    /// Follows redirects of known link shorteners like bit.ly before routing. Sends a network request.
    public var expandsShortURLs: Bool
    /// Order of entries in the browser picker. Browsers missing from this list go after it, sorted by name.
    public var browserPickerOrder: [BrowserTarget]
    /// Entries left out of the browser picker.
    public var hiddenBrowserPickerTargets: Set<BrowserTarget>
    /// Lists each Chromium profile as its own browser picker entry when a browser has more than one profile.
    public var showsBrowserProfiles: Bool
    public var showsMenuBarIcon: Bool
    /// Records opened links in the local history file. Turning it off clears the history.
    public var keepsLinkHistory: Bool

    public init(
        primaryBrowser: BrowserSelection = .browserPicker,
        alternativeBrowser: BrowserSelection = .browserPicker,
        rules: [LinkRule] = [],
        disabledNativeAppLinkHandlers: Set<String> = Set(NativeAppLinkHandler.allCases.filter { !$0.isEnabledByDefault }.map(\.rawValue)),
        removesTrackingParameters: Bool = false,
        expandsShortURLs: Bool = false,
        browserPickerOrder: [BrowserTarget] = [],
        hiddenBrowserPickerTargets: Set<BrowserTarget> = [],
        showsBrowserProfiles: Bool = true,
        showsMenuBarIcon: Bool = true,
        keepsLinkHistory: Bool = false
    ) {
        self.primaryBrowser = primaryBrowser
        self.alternativeBrowser = alternativeBrowser
        self.rules = rules
        self.disabledNativeAppLinkHandlers = disabledNativeAppLinkHandlers
        self.removesTrackingParameters = removesTrackingParameters
        self.expandsShortURLs = expandsShortURLs
        self.browserPickerOrder = browserPickerOrder
        self.hiddenBrowserPickerTargets = hiddenBrowserPickerTargets
        self.showsBrowserProfiles = showsBrowserProfiles
        self.showsMenuBarIcon = showsMenuBarIcon
        self.keepsLinkHistory = keepsLinkHistory
    }

    private enum CodingKeys: String, CodingKey {
        case primaryBrowser
        case alternativeBrowser
        case rules
        case disabledNativeAppLinkHandlers
        case removesTrackingParameters
        case expandsShortURLs
        case browserPickerOrder
        case hiddenBrowserPickerTargets
        case showsBrowserProfiles
        case showsMenuBarIcon
        case keepsLinkHistory
    }

    public init(from decoder: any Decoder) throws {
        let defaults = VeljaSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryBrowser = try container.decodeIfPresent(BrowserSelection.self, forKey: .primaryBrowser) ?? defaults.primaryBrowser
        alternativeBrowser = try container.decodeIfPresent(BrowserSelection.self, forKey: .alternativeBrowser) ?? defaults.alternativeBrowser
        rules = try container.decodeIfPresent([LinkRule].self, forKey: .rules) ?? defaults.rules
        disabledNativeAppLinkHandlers = try container.decodeIfPresent(Set<String>.self, forKey: .disabledNativeAppLinkHandlers)
            ?? defaults.disabledNativeAppLinkHandlers
        removesTrackingParameters = try container.decodeIfPresent(Bool.self, forKey: .removesTrackingParameters)
            ?? defaults.removesTrackingParameters
        expandsShortURLs = try container.decodeIfPresent(Bool.self, forKey: .expandsShortURLs) ?? defaults.expandsShortURLs
        browserPickerOrder = try container.decodeIfPresent([BrowserTarget].self, forKey: .browserPickerOrder) ?? defaults.browserPickerOrder
        hiddenBrowserPickerTargets = try container.decodeIfPresent(Set<BrowserTarget>.self, forKey: .hiddenBrowserPickerTargets)
            ?? defaults.hiddenBrowserPickerTargets
        showsBrowserProfiles = try container.decodeIfPresent(Bool.self, forKey: .showsBrowserProfiles) ?? defaults.showsBrowserProfiles
        showsMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarIcon) ?? defaults.showsMenuBarIcon
        keepsLinkHistory = try container.decodeIfPresent(Bool.self, forKey: .keepsLinkHistory) ?? defaults.keepsLinkHistory
    }

    /// True unless this app link handler is off, either by default or because the user turned it off.
    public func isNativeAppLinkHandlerEnabled(_ handler: NativeAppLinkHandler) -> Bool {
        !disabledNativeAppLinkHandlers.contains(handler.rawValue)
    }

    /// Turns an app link handler on or off.
    public mutating func setNativeAppLinkHandler(_ handler: NativeAppLinkHandler, isEnabled: Bool) {
        if isEnabled {
            disabledNativeAppLinkHandlers.remove(handler.rawValue)
        } else {
            disabledNativeAppLinkHandlers.insert(handler.rawValue)
        }
    }
}
