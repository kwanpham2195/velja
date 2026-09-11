import AppKit
import VeljaCore

/// Provides the "Open Link with Velja" system service, so a selected link in any app can be sent
/// through Velja's rules. Declared under `NSServices` in Info.plist.
@MainActor
final class LinkServiceProvider: NSObject {
    private let linkHandler: IncomingLinkHandler
    private let previousAppTracker: PreviousAppTracker

    init(linkHandler: IncomingLinkHandler, previousAppTracker: PreviousAppTracker) {
        self.linkHandler = linkHandler
        self.previousAppTracker = previousAppTracker
    }

    /// Called by the Services menu. The selector name must match `NSMessage` in Info.plist.
    @objc func openLinkService(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let links = Self.webLinks(from: pasteboard)
        guard !links.isEmpty else {
            error.pointee = "No web link was found in the selection." as NSString
            return
        }
        let sourceApp = LinkSourceApp.detectLinkSourceApp(of: nil, previousApp: previousAppTracker.lastActiveOtherApp)
        for link in links {
            linkHandler.handleIncomingLink(link, sourceApp: sourceApp)
        }
    }

    /// Web links on the pasteboard, as URLs or found in selected text. At most ten, to keep a
    /// large selection from opening dozens of tabs.
    private static func webLinks(from pasteboard: NSPasteboard) -> [URL] {
        let maximumLinkCount = 10
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            let webURLs = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            if !webURLs.isEmpty {
                return Array(webURLs.prefix(maximumLinkCount))
            }
        }
        guard let text = pasteboard.string(forType: .string) else {
            return []
        }
        return Array(LinkTextParser.webLinks(inText: text).prefix(maximumLinkCount))
    }
}
