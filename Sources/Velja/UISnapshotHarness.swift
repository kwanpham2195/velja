#if DEBUG
import AppKit
import SwiftUI
import VeljaCore

/// Debug builds only: renders every settings tab, the rule editor, and the browser picker to PNG
/// files, then quits. Checks the UI without screen recording permission, and never touches the real
/// settings because it uses a temporary support directory.
///
/// Usage: `swift run Velja --ui-snapshots /tmp/velja-snapshots`
@MainActor
final class UISnapshotHarness: NSObject, NSApplicationDelegate {
    private let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    /// The directory passed after `--ui-snapshots`, or `nil` for a normal launch.
    static func requestedSnapshotDirectory() -> URL? {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--ui-snapshots"), arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return URL(filePath: arguments[flagIndex + 1], directoryHint: .isDirectory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try writeSnapshots()
            print("ui-snapshots: wrote snapshots to \(outputDirectory.path(percentEncoded: false))")
        } catch {
            print("ui-snapshots: failed: \(error)")
        }
        NSApp.terminate(nil)
    }

    private func writeSnapshots() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let supportDirectory = FileManager.default.temporaryDirectory.appending(path: "VeljaSnapshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let model = AppModel(supportDirectory: supportDirectory)
        let firstChoice = model.selectableBrowserChoices.first?.target ?? BrowserTarget(bundleIdentifier: "com.apple.Safari")
        model.settings.keepsLinkHistory = true
        model.settings.rules = [
            LinkRule(name: "Work links", urlMatchers: [URLMatcher(kind: .domain, pattern: "atlassian.net"), URLMatcher(kind: .prefix, pattern: "github.com/acme")], action: .openInBrowser(firstChoice)),
            LinkRule(name: "Links from Slack", sourceAppBundleIdentifiers: ["com.tinyspeck.slackmacgap"], action: .showBrowserPicker),
            LinkRule(name: "Broken rule", isEnabled: false, urlMatchers: [URLMatcher(kind: .regex, pattern: "")], action: .showBrowserPicker),
        ]
        model.recordOpenedLink(LinkHistoryEntry(
            date: Date(),
            url: URL(string: "https://github.com/apple/swift/pull/1234")!,
            sourceAppBundleIdentifier: "com.apple.mail",
            sourceAppName: "Mail",
            destinationName: model.browserTitle(for: firstChoice),
            reasonDescription: "Rule: Work links"
        ))

        let linkHandler = IncomingLinkHandler(model: model, browserPicker: BrowserPickerController(previousAppTracker: PreviousAppTracker()))
        let settingsSize = NSSize(width: 680, height: 560)
        let ruleDraft = RuleEditorDraft(rule: model.settings.rules[0], isNewRule: false)
        let pickerModel = BrowserPickerModel(
            request: BrowserPickerRequest(
                url: URL(string: "https://www.github.com/apple/swift/issues?q=is%3Aopen+label%3Abug&utm_source=newsletter")!,
                sourceApp: NSWorkspace.shared.frontmostApplication.map(LinkSourceApp.init(runningApplication:)),
                reason: .primaryBrowser
            ),
            choices: model.visibleBrowserPickerChoices,
            onFinish: { _ in }
        )

        func settingsTab(_ view: some View) -> AnyView {
            AnyView(view.frame(width: settingsSize.width, height: settingsSize.height))
        }
        let snapshots: [(name: String, view: AnyView, size: NSSize?)] = [
            ("settings-window", AnyView(SettingsView(model: model, linkHandler: linkHandler)), settingsSize),
            ("general", settingsTab(GeneralSettingsView(model: model)), settingsSize),
            ("browsers", settingsTab(BrowsersSettingsView(model: model)), settingsSize),
            ("rules", settingsTab(RulesSettingsView(model: model)), settingsSize),
            ("app-links", settingsTab(AppLinksSettingsView(model: model)), settingsSize),
            ("history", settingsTab(HistorySettingsView(model: model, linkHandler: linkHandler)), settingsSize),
            ("rule-editor", AnyView(RuleEditorView(draft: ruleDraft, model: model, onSave: { _ in }, onCancel: {})), NSSize(width: 580, height: 640)),
            ("browser-picker", AnyView(BrowserPickerView(model: pickerModel).background(Color(nsColor: .windowBackgroundColor))), nil),
            ("browser-picker-scrolling", AnyView(BrowserPickerView(model: pickerModel, maximumListHeight: 260).background(Color(nsColor: .windowBackgroundColor))), nil),
        ]
        for snapshot in snapshots {
            try writeSnapshot(of: snapshot.view, size: snapshot.size, to: outputDirectory.appending(path: "\(snapshot.name).png"))
        }
    }

    /// Hosts the view in a window, lets SwiftUI lay it out, and draws the window content into a PNG.
    /// `size` of `nil` uses the view's own fitting size.
    private func writeSnapshot(of view: AnyView, size: NSSize?, to fileURL: URL) throws {
        let hostingView = NSHostingView(rootView: view)
        let contentSize = size ?? hostingView.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: contentSize), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hostingView.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: fileURL)
    }
}
#endif
