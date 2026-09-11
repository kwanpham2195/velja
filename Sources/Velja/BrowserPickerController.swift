import AppKit
import SwiftUI
import VeljaCore

/// A borderless floating panel that takes keyboard focus without activating Velja, so the app the
/// link came from stays active, like Spotlight.
final class BrowserPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows the browser picker near the mouse pointer and reports what the user chose. Links that
/// arrive while a picker is open wait in line and get their own picker afterwards.
@MainActor
final class BrowserPickerController: NSObject, NSWindowDelegate {
    private struct PendingPicker {
        var request: BrowserPickerRequest
        var choices: [BrowserChoice]
        var completion: (BrowserPickerOutcome) -> Void
    }

    private let previousAppTracker: PreviousAppTracker
    private var pendingPickers: [PendingPicker] = []
    private var panel: BrowserPickerPanel?
    private var model: BrowserPickerModel?
    private var keyDownMonitor: Any?
    private var outsideClickMonitor: Any?
    /// Set while the picker closes because the user clicked in another app or switched away from the picker.
    private var isClosingForOutsideClick = false

    /// Delay before showing a queued picker, so the browser opened from the previous picker has usually
    /// activated first; a later activation is handled in `windowDidResignKey(_:)`.
    private let queuedPickerDelay: Duration = .milliseconds(350)

    /// The browser last opened in the foreground from a picker; it may come forward after the next picker shows.
    private var recentlyOpenedBrowser: (bundleIdentifier: String, openedAt: ContinuousClock.Instant)?
    /// How long the picker waits after losing focus, so the app that took focus is known before it cancels.
    private let resignKeyGracePeriod: Duration = .milliseconds(150)
    /// How long after a picker opened a browser that browser may come forward without cancelling the next picker.
    private let browserActivationWindow: Duration = .seconds(10)

    init(previousAppTracker: PreviousAppTracker) {
        self.previousAppTracker = previousAppTracker
        super.init()
    }

    /// Shows a picker for the link, or queues it when a picker is already open.
    func presentBrowserPicker(for request: BrowserPickerRequest, choices: [BrowserChoice], completion: @escaping (BrowserPickerOutcome) -> Void) {
        pendingPickers.append(PendingPicker(request: request, choices: choices, completion: completion))
        if model == nil {
            showNextPicker()
        }
    }

    private func showNextPicker() {
        guard model == nil, !pendingPickers.isEmpty else {
            return
        }
        let pendingPicker = pendingPickers.removeFirst()
        let pickerModel = BrowserPickerModel(request: pendingPicker.request, choices: pendingPicker.choices) { [weak self] outcome in
            self?.closePicker()
            switch outcome {
            case .openInBrowser(let target, inBackground: false), .alwaysOpenInBrowser(let target):
                // The browser comes to the front on its own, possibly after a queued picker has shown.
                self?.recentlyOpenedBrowser = (target.bundleIdentifier, .now)
            case .openInBrowser(_, inBackground: true), .copyLink, .cancel:
                // Nothing else will take focus; without this, keystrokes would go to Velja, which has no window.
                // A click in another app already brings that app forward, so it is left alone.
                if self?.pendingPickers.isEmpty == true, self?.isClosingForOutsideClick == false {
                    self?.previousAppTracker.returnFocusToPreviousApp()
                }
            }
            self?.isClosingForOutsideClick = false
            pendingPicker.completion(outcome)
            self?.showQueuedPickerAfterDelay()
        }
        model = pickerModel

        let visibleFrame = Self.visibleFrameOfPointerScreen()
        let availableHeight = visibleFrame.height - 2 * Self.screenMargin
        var hostingView = NSHostingView(rootView: BrowserPickerView(model: pickerModel))
        if hostingView.fittingSize.height > availableHeight {
            // Too many entries for the screen: measure the header and footer alone, and give the rest to a scrolling list.
            let emptyPickerModel = BrowserPickerModel(request: pendingPicker.request, choices: [], onFinish: { _ in })
            let headerAndFooterHeight = NSHostingView(rootView: BrowserPickerView(model: emptyPickerModel)).fittingSize.height
            let listHeight = max(availableHeight - headerAndFooterHeight, 120)
            hostingView = NSHostingView(rootView: BrowserPickerView(model: pickerModel, maximumListHeight: listHeight))
        }
        let contentSize = hostingView.fittingSize
        let pickerPanel = BrowserPickerPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pickerPanel.contentView = hostingView
        pickerPanel.isOpaque = false
        pickerPanel.backgroundColor = .clear
        pickerPanel.hasShadow = true
        pickerPanel.level = .floating
        pickerPanel.isFloatingPanel = true
        pickerPanel.hidesOnDeactivate = false
        pickerPanel.becomesKeyOnlyIfNeeded = false
        pickerPanel.isReleasedWhenClosed = false
        pickerPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        pickerPanel.title = "Choose a Browser"
        pickerPanel.setFrameOrigin(Self.pickerOrigin(forContentSize: contentSize, visibleFrame: visibleFrame))
        pickerPanel.delegate = self
        panel = pickerPanel

        installEventMonitors(for: pickerPanel, model: pickerModel)
        pickerPanel.orderFrontRegardless()
        pickerPanel.makeKey()
        pickerPanel.invalidateShadow()
    }

    private func showQueuedPickerAfterDelay() {
        guard !pendingPickers.isEmpty else {
            return
        }
        Task { @MainActor [weak self, queuedPickerDelay] in
            try? await Task.sleep(for: queuedPickerDelay)
            self?.showNextPicker()
        }
    }

    private func closePicker() {
        removeEventMonitors()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    /// Space kept between the picker and the edges of the screen.
    private static let screenMargin: CGFloat = 8

    /// The usable area (without menu bar and Dock) of the screen the pointer is on.
    private static func visibleFrameOfPointerScreen() -> NSRect {
        let pointerLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointerLocation, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Places the panel's top-left corner just above and left of the pointer, kept inside the visible frame.
    private static func pickerOrigin(forContentSize contentSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        let pointerLocation = NSEvent.mouseLocation
        var origin = NSPoint(x: pointerLocation.x - 24, y: pointerLocation.y - contentSize.height + 24)
        origin.x = min(max(origin.x, visibleFrame.minX + screenMargin), visibleFrame.maxX - contentSize.width - screenMargin)
        origin.y = min(max(origin.y, visibleFrame.minY + screenMargin), visibleFrame.maxY - contentSize.height - screenMargin)
        return origin
    }

    // MARK: Keyboard and mouse

    private func installEventMonitors(for pickerPanel: BrowserPickerPanel, model pickerModel: BrowserPickerModel) {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak pickerPanel, weak pickerModel] event in
            let isHandled = MainActor.assumeIsolated { () -> Bool in
                guard let pickerPanel, let pickerModel, event.window === pickerPanel else {
                    return false
                }
                Self.handlePickerKeyDown(event, model: pickerModel)
                // Swallow every key while the picker has focus, so shortcuts like ⌘Q never reach the app.
                return true
            }
            return isHandled ? nil : event
        }
        // Clicks in other apps cancel the picker. Mouse events can be monitored without accessibility access.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak pickerModel] _ in
            MainActor.assumeIsolated {
                guard let pickerModel else {
                    return
                }
                self?.cancelPickerAfterFocusMovedAway(pickerModel)
            }
        }
    }

    /// Switching away, for example with ⌘-Tab, cancels the picker after a short wait so it does not float over
    /// every Space. When the browser chosen in the previous picker is what came forward, the picker takes focus
    /// back instead, so a queued link is not lost. Context menus inside the picker do not make the panel resign key.
    func windowDidResignKey(_ notification: Notification) {
        guard let model, (notification.object as? NSWindow) === panel else {
            return
        }
        Task { @MainActor [weak self, weak model, resignKeyGracePeriod] in
            try? await Task.sleep(for: resignKeyGracePeriod)
            guard let self, let model, self.model === model, !model.isFinished,
                  let panel = self.panel, !panel.isKeyWindow else {
                return
            }
            if self.isRecentlyOpenedBrowserFrontmost() {
                VeljaLog.routing.info("Kept the browser picker open after the previously chosen browser came forward")
                panel.makeKeyAndOrderFront(nil)
            } else {
                self.cancelPickerAfterFocusMovedAway(model)
            }
        }
    }

    /// True when the frontmost app is the browser a picker opened less than `browserActivationWindow` ago.
    private func isRecentlyOpenedBrowserFrontmost() -> Bool {
        guard let recentlyOpenedBrowser, recentlyOpenedBrowser.openedAt.duration(to: .now) < browserActivationWindow else {
            return false
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == recentlyOpenedBrowser.bundleIdentifier
    }

    /// Cancels without handing focus back, because the other app already has it.
    private func cancelPickerAfterFocusMovedAway(_ pickerModel: BrowserPickerModel) {
        guard !pickerModel.isFinished else {
            return
        }
        isClosingForOutsideClick = true
        pickerModel.finish(.cancel)
    }

    private func removeEventMonitors() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        keyDownMonitor = nil
        outsideClickMonitor = nil
    }

    /// Key codes of the number keys 1–9 on the main keyboard and the keypad, by picker position.
    private static let numberKeyCodes: [[UInt16]] = [
        [18, 83], [19, 84], [20, 85], [21, 86], [23, 87], [22, 88], [26, 89], [28, 91], [25, 92],
    ]

    /// Key codes that keep acting while held: Down arrow, Up arrow, and Tab.
    private static let repeatingKeyCodes: Set<UInt16> = [125, 126, 48]

    private static func handlePickerKeyDown(_ event: NSEvent, model: BrowserPickerModel) {
        // A key still held from the app the link came from, such as Return, must not choose or close anything.
        if event.isARepeat, !repeatingKeyCodes.contains(event.keyCode) {
            return
        }
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let character = event.charactersIgnoringModifiers?.lowercased()

        if modifierFlags.contains(.command) {
            switch character {
            case "c":
                model.finish(.copyLink)
                return
            case "w", ".":
                model.finish(.cancel)
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 53: // Escape
            model.finish(.cancel)
        case 36, 76, 49: // Return, keypad Enter, Space
            model.chooseEntry(at: model.selectedIndex, modifierFlags: modifierFlags)
        case 125: // Down arrow
            model.moveSelection(by: 1)
        case 126: // Up arrow
            model.moveSelection(by: -1)
        case 48: // Tab
            model.moveSelection(by: modifierFlags.contains(.shift) ? -1 : 1)
        default:
            if let position = numberKeyCodes.firstIndex(where: { $0.contains(event.keyCode) }) {
                model.chooseEntry(at: position, modifierFlags: modifierFlags)
            }
        }
    }
}
