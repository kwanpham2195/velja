import AppKit
import VeljaCore

/// The menu bar icon and its menu: default browser status, clipboard link, browsers, recent links,
/// settings, and quit. The menu is rebuilt every time it opens, so it always reflects current state.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let model: AppModel
    private let linkHandler: IncomingLinkHandler
    private let showSettings: () -> Void
    private var statusItem: NSStatusItem?

    init(model: AppModel, linkHandler: IncomingLinkHandler, showSettings: @escaping () -> Void) {
        self.model = model
        self.linkHandler = linkHandler
        self.showSettings = showSettings
    }

    /// Adds or removes the menu bar icon to match the "Show menu bar icon" setting.
    func updateMenuBarIconVisibility() {
        if model.settings.showsMenuBarIcon {
            guard statusItem == nil else {
                return
            }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Linkfork")
            image?.isTemplate = true
            item.button?.image = image
            item.button?.toolTip = "Linkfork"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
            VeljaLog.system.info("Menu bar icon added (button present: \(item.button != nil, privacy: .public))")
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            VeljaLog.system.info("Menu bar icon removed")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        model.refreshDefaultBrowserStatus()
        model.refreshInstalledBrowsers()

        if !model.isVeljaDefaultBrowser {
            menu.addItem(makeItem("Set Linkfork as Default Browser…", action: #selector(makeVeljaDefaultBrowser)))
            menu.addItem(.separator())
        }

        menu.addItem(makeItem("Open Link from Clipboard", action: #selector(openClipboardLink)))

        let browsersItem = NSMenuItem(title: "Open Browser", action: nil, keyEquivalent: "")
        let browsersMenu = NSMenu()
        for (index, choice) in model.visibleBrowserPickerChoices.enumerated() {
            let item = makeItem(choice.title, action: #selector(launchBrowser(_:)))
            item.image = Self.menuIcon(from: choice.icon)
            item.representedObject = choice.target
            if index < 9 {
                item.keyEquivalent = "\(index + 1)"
                item.keyEquivalentModifierMask = [.option]
            }
            browsersMenu.addItem(item)
        }
        browsersItem.submenu = browsersMenu
        menu.addItem(browsersItem)

        if model.settings.keepsLinkHistory, !model.linkHistory.entries.isEmpty {
            let recentItem = NSMenuItem(title: "Recent Links", action: nil, keyEquivalent: "")
            let recentMenu = NSMenu()
            for entry in model.linkHistory.entries.prefix(10) {
                let item = makeItem(Self.shortLinkTitle(for: entry.url), action: #selector(reopenRecentLink(_:)))
                item.toolTip = entry.url.absoluteString
                item.representedObject = entry.url
                recentMenu.addItem(item)
            }
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }

        menu.addItem(.separator())
        let settingsItem = makeItem("Settings…", action: #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Quit Linkfork", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    /// Enables "Open Link from Clipboard" from the clipboard's types alone; reading its contents here, every
    /// time the menu opens, could show the macOS paste permission alert.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(openClipboardLink) else {
            return true
        }
        return NSPasteboard.general.availableType(from: [.URL, .string]) != nil
    }

    // MARK: Actions

    @objc private func makeVeljaDefaultBrowser() {
        Task {
            do {
                try await DefaultBrowserSetting.makeVeljaDefaultBrowser()
            } catch {
                VeljaLog.system.error("Default browser change declined or failed: \(error.localizedDescription, privacy: .public)")
            }
            model.refreshDefaultBrowserStatus()
        }
    }

    @objc private func openClipboardLink() {
        guard let url = Self.clipboardLink() else {
            NSSound.beep()
            return
        }
        linkHandler.handleIncomingLink(url, sourceApp: nil)
    }

    @objc private func launchBrowser(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? BrowserTarget else {
            return
        }
        Task {
            do {
                try await LinkOpener.launchBrowser(target)
            } catch {
                VeljaLog.routing.error("Could not launch \(target.bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
            }
        }
    }

    @objc private func reopenRecentLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        linkHandler.showBrowserPicker(for: url, sourceApp: nil)
    }

    @objc private func openSettings() {
        showSettings()
    }

    // MARK: Helpers

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// The first web link on the clipboard, as a URL or as text. Reads the contents, so call it only on a user action.
    private static func clipboardLink() -> URL? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let webURL = urls.first(where: { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }) {
            return webURL
        }
        guard let text = pasteboard.string(forType: .string) else {
            return nil
        }
        return LinkTextParser.webLink(fromText: text)
    }

    private static func shortLinkTitle(for url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        let path = url.path(percentEncoded: false)
        let title = path.count > 1 ? host + path : host
        return title.count > 60 ? String(title.prefix(57)) + "…" : title
    }

    private static func menuIcon(from icon: NSImage) -> NSImage {
        let resizedIcon = icon.copy() as? NSImage ?? icon
        resizedIcon.size = NSSize(width: 16, height: 16)
        return resizedIcon
    }
}
