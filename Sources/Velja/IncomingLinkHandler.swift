import AppKit
import VeljaCore

/// Takes every link that reaches Velja, from clicks in other apps, `linkfork:open` URLs, the Services
/// menu, the clipboard, or the history, and opens it where the settings say.
///
/// The steps: expand short links, remove tracking parameters, ask ``LinkRouter`` for a decision, then
/// open the link or show the browser picker.
@MainActor
final class IncomingLinkHandler {
    private let model: AppModel
    private let browserPicker: BrowserPickerController
    private let shortURLResolver = URLSessionShortURLRedirectResolver()

    init(model: AppModel, browserPicker: BrowserPickerController) {
        self.model = model
        self.browserPicker = browserPicker
    }

    /// Routes a link clicked in another app. Reads the Fn key right away, before any network delay.
    func handleIncomingLink(_ url: URL, sourceApp: LinkSourceApp?) {
        let isAlternativeBrowserKeyPressed = NSEvent.modifierFlags.contains(.function)
        VeljaLog.routing.info("Incoming link \(url.absoluteString, privacy: .private) from \(sourceApp?.bundleIdentifier ?? "unknown app", privacy: .public)")
        Task {
            let preparedURL = await prepareLink(url)
            model.refreshInstalledBrowsers()
            let context = LinkRoutingContext(
                sourceAppBundleIdentifier: sourceApp?.bundleIdentifier,
                isAlternativeBrowserKeyPressed: isAlternativeBrowserKeyPressed,
                availableBrowserTargets: model.availableBrowserTargets,
                installedAppBundleIdentifiers: Self.installedNativeAppBundleIdentifiers()
            )
            let decision = LinkRouter.routeIncomingLink(preparedURL, settings: model.settings, context: context)
            await carryOut(decision, sourceApp: sourceApp)
        }
    }

    /// Handles `linkfork:open?url=…`. A named browser must be an installed browser; otherwise the
    /// picker is shown, so the command cannot open links in arbitrary apps.
    func handleVeljaOpenCommand(_ command: VeljaOpenCommand, sourceApp: LinkSourceApp?) {
        guard command.forcesBrowserPicker || command.browserTarget != nil else {
            handleIncomingLink(command.url, sourceApp: sourceApp)
            return
        }
        Task {
            let preparedURL = await prepareLink(command.url)
            model.refreshInstalledBrowsers()
            let decision: LinkRoutingDecision
            if !command.forcesBrowserPicker, let target = command.browserTarget, model.availableBrowserTargets.contains(target) {
                decision = .openInBrowser(target, url: preparedURL, reason: .veljaOpenCommand)
            } else {
                decision = .showBrowserPicker(url: preparedURL, reason: .veljaOpenCommand)
            }
            await carryOut(decision, sourceApp: sourceApp)
        }
    }

    /// Shows the browser picker for a link regardless of rules, for example from the link history.
    func showBrowserPicker(for url: URL, sourceApp: LinkSourceApp?) {
        model.refreshInstalledBrowsers()
        presentPicker(for: BrowserPickerRequest(url: url, sourceApp: sourceApp, reason: .primaryBrowser))
    }

    // MARK: Steps

    private func prepareLink(_ url: URL) async -> URL {
        var preparedURL = url
        if model.settings.expandsShortURLs {
            preparedURL = await ShortURLExpander.expandShortURL(preparedURL, using: shortURLResolver)
        }
        if model.settings.removesTrackingParameters {
            preparedURL = TrackingParameterCleaner.removeTrackingParameters(from: preparedURL)
        }
        return preparedURL
    }

    private func carryOut(_ decision: LinkRoutingDecision, sourceApp: LinkSourceApp?) async {
        switch decision {
        case .openInBrowser(let target, let url, let reason):
            VeljaLog.routing.info("Opening in \(target.bundleIdentifier, privacy: .public) (\(reason.historyDescription, privacy: .public))")
            await openLink(url, in: target, inBackground: false, sourceApp: sourceApp, reason: reason)
        case .openInNativeApp(let appBundleIdentifier, let nativeAppURL, let originalURL, let handler):
            VeljaLog.routing.info("Opening in app \(appBundleIdentifier, privacy: .public) via \(handler.rawValue, privacy: .public) app link")
            do {
                try await LinkOpener.openLinkInNativeApp(nativeAppURL, appBundleIdentifier: appBundleIdentifier)
                recordHistory(url: originalURL, sourceApp: sourceApp, destinationName: handler.displayName, reasonDescription: "App link")
            } catch {
                VeljaLog.routing.error("Could not open \(handler.rawValue, privacy: .public) app link: \(error.localizedDescription, privacy: .public)")
                presentPicker(for: BrowserPickerRequest(url: originalURL, sourceApp: sourceApp, reason: .primaryBrowser))
            }
        case .showBrowserPicker(let url, let reason):
            VeljaLog.routing.info("Showing browser picker (\(reason.historyDescription, privacy: .public))")
            presentPicker(for: BrowserPickerRequest(url: url, sourceApp: sourceApp, reason: reason))
        }
    }

    private func presentPicker(for request: BrowserPickerRequest) {
        let choices = model.visibleBrowserPickerChoices
        guard !choices.isEmpty else {
            VeljaLog.routing.error("No browsers are installed; cannot open link")
            NSSound.beep()
            return
        }
        browserPicker.presentBrowserPicker(for: request, choices: choices) { [weak self] outcome in
            guard let self else {
                return
            }
            Task {
                await self.carryOut(outcome, for: request)
            }
        }
    }

    private func carryOut(_ outcome: BrowserPickerOutcome, for request: BrowserPickerRequest) async {
        switch outcome {
        case .openInBrowser(let target, let inBackground):
            await openLink(request.url, in: target, inBackground: inBackground, sourceApp: request.sourceApp, reason: request.reason, pickedInPicker: true)
        case .alwaysOpenInBrowser(let target):
            if let rule = LinkRule.makeAlwaysOpenDomainRule(for: request.url, target: target, browserName: model.browserTitle(for: target)) {
                model.insertRuleAtTop(rule)
                VeljaLog.routing.info("Added rule for \(target.bundleIdentifier, privacy: .public) from the browser picker")
            }
            await openLink(request.url, in: target, inBackground: false, sourceApp: request.sourceApp, reason: request.reason, pickedInPicker: true)
        case .copyLink:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(request.url.absoluteString, forType: .string)
        case .cancel:
            break
        }
    }

    private func openLink(
        _ url: URL,
        in target: BrowserTarget,
        inBackground: Bool,
        sourceApp: LinkSourceApp?,
        reason: LinkRoutingReason,
        pickedInPicker: Bool = false
    ) async {
        do {
            try await LinkOpener.openLink(url, in: target, inBackground: inBackground)
            VeljaLog.routing.info("Opened link in \(target.bundleIdentifier, privacy: .public) profile \(target.profileDirectory ?? "none", privacy: .public)")
            let reasonDescription = pickedInPicker ? "Chosen in picker" : reason.historyDescription
            recordHistory(url: url, sourceApp: sourceApp, destinationName: model.browserTitle(for: target), reasonDescription: reasonDescription)
        } catch {
            VeljaLog.routing.error("Could not open link in \(target.bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Let the user pick another browser instead of losing the link.
            if pickedInPicker {
                NSSound.beep()
                presentPicker(for: BrowserPickerRequest(url: url, sourceApp: sourceApp, reason: reason))
            } else {
                presentPicker(for: BrowserPickerRequest(url: url, sourceApp: sourceApp, reason: .unavailableBrowser(target)))
            }
        }
    }

    private func recordHistory(url: URL, sourceApp: LinkSourceApp?, destinationName: String, reasonDescription: String) {
        model.recordOpenedLink(LinkHistoryEntry(
            date: Date(),
            url: url,
            sourceAppBundleIdentifier: sourceApp?.bundleIdentifier,
            sourceAppName: sourceApp?.name,
            destinationName: destinationName,
            reasonDescription: reasonDescription
        ))
    }

    /// Bundle identifiers of installed apps that app links can open in.
    private static func installedNativeAppBundleIdentifiers() -> Set<String> {
        let candidates = NativeAppLinkHandler.allCases.flatMap(\.appBundleIdentifiers)
        return Set(candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }
}
