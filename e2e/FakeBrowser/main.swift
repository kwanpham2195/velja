// A stand-in browser for Velja's end-to-end tests (scripts/e2e.sh).
//
// It registers for http and https like a real browser, so Velja lists it and can route links to
// it. Every link it receives and every launch argument it gets is appended to the file named by
// the `VeljaE2ERecordFile` key in its Info.plist, one tab-separated line per event:
//
//   launch<TAB>argument<TAB>argument…   when it starts (Chromium-style profile launches pass
//                                        `--profile-directory=…` and the link as arguments)
//   open<TAB>link                        for each link or file it is asked to open
//   send<TAB>link                        in sender mode, below
//
// Sender mode, `--send-link-to-velja <Velja.app path> <link>`, opens the link with Velja and quits,
// so Velja sees this app as the app the link was clicked in.
import AppKit

let recordFileURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "VeljaE2ERecordFile") as? String)
    .map { URL(filePath: $0) }

/// Appends one line with a single `O_APPEND` write, so lines from several instances never interleave.
@MainActor
func appendRecordLine(_ fields: [String]) {
    guard let recordFileURL else {
        return
    }
    let line = fields.joined(separator: "\t") + "\n"
    let descriptor = open(recordFileURL.path(percentEncoded: false), O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard descriptor >= 0 else {
        return
    }
    _ = line.withCString { write(descriptor, $0, strlen($0)) }
    close(descriptor)
}

@MainActor
final class FakeBrowserDelegate: NSObject, NSApplicationDelegate {
    private var quitTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let flagIndex = arguments.firstIndex(of: "--send-link-to-velja"), arguments.count > flagIndex + 2,
           let link = URL(string: arguments[flagIndex + 2]) {
            sendLinkToVelja(link, veljaAppURL: URL(filePath: arguments[flagIndex + 1]))
            return
        }
        appendRecordLine(["launch"] + arguments)
        scheduleQuit()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            appendRecordLine(["open", url.absoluteString])
        }
        scheduleQuit()
    }

    private func sendLinkToVelja(_ link: URL, veljaAppURL: URL) {
        appendRecordLine(["send", link.absoluteString])
        Task {
            _ = try? await NSWorkspace.shared.open([link], withApplicationAt: veljaAppURL, configuration: NSWorkspace.OpenConfiguration())
            // Stay alive briefly: Velja looks up this process by its ID when the link arrives.
            try? await Task.sleep(for: .seconds(2))
            NSApp.terminate(nil)
        }
    }

    /// Quits a few seconds after the last event, so test runs do not leave instances behind.
    private func scheduleQuit() {
        quitTask?.cancel()
        quitTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                NSApp.terminate(nil)
            }
        }
    }
}

let fakeBrowserDelegate = FakeBrowserDelegate()
NSApplication.shared.delegate = fakeBrowserDelegate
NSApplication.shared.run()
