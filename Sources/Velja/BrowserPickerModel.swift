import AppKit
import Observation
import VeljaCore

/// A link waiting for the user to pick a browser.
struct BrowserPickerRequest {
    var url: URL
    var sourceApp: LinkSourceApp?
    /// Why the picker is shown; kept for the link history.
    var reason: LinkRoutingReason
}

/// What the user did in the browser picker.
enum BrowserPickerOutcome {
    case openInBrowser(BrowserTarget, inBackground: Bool)
    /// Open the link and add a rule so links on this domain always open in the browser.
    case alwaysOpenInBrowser(BrowserTarget)
    case copyLink
    case cancel
}

/// State of the browser picker panel: the link, the entries, and the highlighted entry.
@MainActor
@Observable
final class BrowserPickerModel {
    let request: BrowserPickerRequest
    let choices: [BrowserChoice]
    var selectedIndex = 0

    @ObservationIgnored private let onFinish: (BrowserPickerOutcome) -> Void
    @ObservationIgnored private(set) var isFinished = false

    init(request: BrowserPickerRequest, choices: [BrowserChoice], onFinish: @escaping (BrowserPickerOutcome) -> Void) {
        self.request = request
        self.choices = choices
        self.onFinish = onFinish
    }

    /// Host shown in large type at the top, or the file name for local files.
    var linkTitle: String {
        if let host = request.url.host(percentEncoded: false), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return request.url.lastPathComponent.isEmpty ? request.url.absoluteString : request.url.lastPathComponent
    }

    /// Finishes once. Later calls, such as the panel losing focus after a browser opened, are ignored.
    func finish(_ outcome: BrowserPickerOutcome) {
        guard !isFinished else {
            return
        }
        isFinished = true
        onFinish(outcome)
    }

    /// Opens the entry at `index` using the modifier keys held right now:
    /// Command adds an "always open" rule, Control or Shift opens in the background.
    func chooseEntry(at index: Int, modifierFlags: NSEvent.ModifierFlags) {
        guard choices.indices.contains(index) else {
            return
        }
        let target = choices[index].target
        if modifierFlags.contains(.command) {
            finish(.alwaysOpenInBrowser(target))
        } else {
            let inBackground = modifierFlags.contains(.control) || modifierFlags.contains(.shift)
            finish(.openInBrowser(target, inBackground: inBackground))
        }
    }

    func moveSelection(by offset: Int) {
        guard !choices.isEmpty else {
            return
        }
        selectedIndex = (selectedIndex + offset + choices.count) % choices.count
    }
}
