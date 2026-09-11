import AppKit

/// The app a link was clicked in, such as Slack or Mail.
struct LinkSourceApp {
    var bundleIdentifier: String?
    var name: String
    var icon: NSImage?

    init(runningApplication: NSRunningApplication) {
        bundleIdentifier = runningApplication.bundleIdentifier
        name = runningApplication.localizedName ?? runningApplication.bundleIdentifier ?? "Unknown App"
        icon = runningApplication.icon
    }

    /// Detects which app sent an Apple event, such as the "open URL" event for a clicked link.
    ///
    /// Uses the sender's process ID from the event. When that process is not a user-facing app (a
    /// background helper, or the `open` command in a terminal), falls back to the frontmost app, which
    /// is where the user clicked, or to `previousApp` when macOS already brought Velja to the front.
    /// Velja itself is never reported.
    @MainActor
    static func detectLinkSourceApp(of appleEvent: NSAppleEventDescriptor?, previousApp: NSRunningApplication?) -> LinkSourceApp? {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        if let senderProcessIdentifier = appleEvent?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
           senderProcessIdentifier > 0,
           senderProcessIdentifier != ownProcessIdentifier,
           let senderApp = NSRunningApplication(processIdentifier: senderProcessIdentifier),
           senderApp.bundleIdentifier != nil,
           senderApp.activationPolicy != .prohibited {
            return LinkSourceApp(runningApplication: senderApp)
        }
        if let frontmostApp = NSWorkspace.shared.frontmostApplication, frontmostApp.processIdentifier != ownProcessIdentifier {
            return LinkSourceApp(runningApplication: frontmostApp)
        }
        guard let previousApp, !previousApp.isTerminated, previousApp.processIdentifier != ownProcessIdentifier else {
            return nil
        }
        return LinkSourceApp(runningApplication: previousApp)
    }
}
