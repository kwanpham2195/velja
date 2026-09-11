import AppKit
import VeljaCore

/// Wires Velja together and receives links from macOS: "open URL" Apple events for web links and
/// `linkfork:` URLs, and "open documents" for HTML files and URLs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let previousAppTracker = PreviousAppTracker()
    private lazy var browserPicker = BrowserPickerController(previousAppTracker: previousAppTracker)
    private lazy var linkHandler = IncomingLinkHandler(model: model, browserPicker: browserPicker)
    private lazy var settingsWindowController = SettingsWindowController(model: model, linkHandler: linkHandler)
    private lazy var statusMenuController = StatusMenuController(model: model, linkHandler: linkHandler) { [weak self] in
        self?.showSettingsWindow()
    }
    private lazy var linkServiceProvider = LinkServiceProvider(linkHandler: linkHandler, previousAppTracker: previousAppTracker)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Registered before launch finishes so the link that launched Velja is not missed.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenURLAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        NSApp.mainMenu = MainMenuBuilder.makeMainMenu(settingsTarget: self, settingsAction: #selector(showSettingsFromMenu(_:)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = linkServiceProvider
        NSUpdateDynamicServices()

        model.onSettingsChanged = { [weak self] in
            self?.statusMenuController.updateMenuBarIconVisibility()
        }
        statusMenuController.updateMenuBarIconVisibility()

        let isOrdinaryLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? false
        let hasNoVisibleEntryPoint = !model.settings.showsMenuBarIcon && !Self.wasLaunchedAsLoginItem()
        if model.isFirstLaunch || (isOrdinaryLaunch && hasNoVisibleEntryPoint) {
            showSettingsWindow()
        }
    }

    /// Opening Velja again from Finder or Spotlight shows the settings, which is the only way in
    /// when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// HTML files opened with Velja, for example by double-clicking them in Finder, and URLs that
    /// arrive as "open documents", such as `open -a Linkfork <url>`.
    func application(_ application: NSApplication, open urls: [URL]) {
        let sourceApp = LinkSourceApp.detectLinkSourceApp(
            of: NSAppleEventManager.shared().currentAppleEvent,
            previousApp: previousAppTracker.lastActiveOtherApp
        )
        for url in urls {
            if url.isFileURL {
                linkHandler.handleIncomingLink(url, sourceApp: sourceApp)
                continue
            }
            switch url.scheme?.lowercased() {
            case VeljaOpenCommand.urlScheme:
                handleVeljaURL(url, sourceApp: sourceApp)
            case "http", "https":
                linkHandler.handleIncomingLink(url, sourceApp: sourceApp)
            default:
                VeljaLog.routing.error("Ignored an opened URL with an unsupported scheme: \(url.scheme ?? "none", privacy: .public)")
            }
        }
    }

    @objc private func handleOpenURLAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            VeljaLog.routing.error("Received an open URL event without a readable URL")
            return
        }
        let sourceApp = LinkSourceApp.detectLinkSourceApp(of: event, previousApp: previousAppTracker.lastActiveOtherApp)
        if url.scheme?.lowercased() == VeljaOpenCommand.urlScheme {
            handleVeljaURL(url, sourceApp: sourceApp)
            return
        }
        linkHandler.handleIncomingLink(url, sourceApp: sourceApp)
    }

    /// Runs a `linkfork:` URL as a command; an invalid one is refused with a beep so it never reaches a browser.
    private func handleVeljaURL(_ url: URL, sourceApp: LinkSourceApp?) {
        guard let command = VeljaOpenCommand.parseVeljaOpenCommand(url) else {
            VeljaLog.routing.error("Ignored an invalid linkfork: URL")
            NSSound.beep()
            return
        }
        linkHandler.handleVeljaOpenCommand(command, sourceApp: sourceApp)
    }

    @objc private func showSettingsFromMenu(_ sender: Any?) {
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        settingsWindowController.showSettingsWindow()
    }

    /// True when macOS opened Velja as a login item, detected from the launch Apple event.
    private static func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
