import AppKit

/// Remembers the last app other than Velja that was active.
///
/// macOS activates Velja when it hands it a link, so by the time the link arrives the frontmost app
/// is Velja itself. This tracker still knows where the user clicked, which is used to detect the
/// link's source app and to give focus back after the browser picker closes without opening a browser.
@MainActor
final class PreviousAppTracker {
    private(set) var lastActiveOtherApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init() {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        if let frontmostApp = NSWorkspace.shared.frontmostApplication, frontmostApp.processIdentifier != ownProcessIdentifier {
            lastActiveOtherApp = frontmostApp
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  activatedApp.processIdentifier != ownProcessIdentifier else {
                return
            }
            MainActor.assumeIsolated {
                self?.lastActiveOtherApp = activatedApp
            }
        }
    }

    /// Gives focus back to the app the user was in, when Velja is active and has no settings window
    /// open. Used after the browser picker closes without bringing a browser forward.
    func returnFocusToPreviousApp() {
        guard NSApp.isActive,
              !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
              let lastActiveOtherApp, !lastActiveOtherApp.isTerminated else {
            return
        }
        lastActiveOtherApp.activate(options: [])
    }
}
