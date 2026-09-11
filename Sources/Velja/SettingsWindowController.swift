import AppKit
import SwiftUI

/// Owns the settings window and brings it to the front, even though Velja has no Dock icon.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let linkHandler: IncomingLinkHandler
    private var window: NSWindow?

    init(model: AppModel, linkHandler: IncomingLinkHandler) {
        self.model = model
        self.linkHandler = linkHandler
    }

    func showSettingsWindow() {
        model.refreshInstalledBrowsers()
        model.refreshDefaultBrowserStatus()
        let settingsWindow = window ?? makeSettingsWindow()
        window = settingsWindow
        NSApp.activate()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsView(model: model, linkHandler: linkHandler))
        let settingsWindow = NSWindow(contentViewController: hostingController)
        settingsWindow.title = "Velja Settings"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.setContentSize(NSSize(width: 680, height: 560))
        settingsWindow.contentMinSize = NSSize(width: 600, height: 460)
        settingsWindow.center()
        settingsWindow.setFrameAutosaveName("VeljaSettingsWindow")
        return settingsWindow
    }
}
