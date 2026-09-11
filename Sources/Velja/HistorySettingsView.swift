import AppKit
import SwiftUI
import VeljaCore

/// The link history: recently opened links, where they came from, and where they went.
/// Useful for checking which app Velja detected as a link's source when writing rules.
struct HistorySettingsView: View {
    @Bindable var model: AppModel
    let linkHandler: IncomingLinkHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.settings.keepsLinkHistory {
                ContentUnavailableView {
                    Label("Link History Is Off", systemImage: "clock")
                } description: {
                    Text("Turn it on to see recent links, the app each one came from, and where it opened. History stays on this Mac.")
                } actions: {
                    Button("Turn On Link History") {
                        model.settings.keepsLinkHistory = true
                    }
                }
            } else if model.linkHistory.entries.isEmpty {
                ContentUnavailableView("No Links Yet", systemImage: "clock", description: Text("Links you open appear here."))
            } else {
                List(model.linkHistory.entries) { entry in
                    HistoryRow(entry: entry)
                        .contextMenu {
                            Button("Open Again…") {
                                linkHandler.showBrowserPicker(for: entry.url, sourceApp: nil)
                            }
                            Button("Copy Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
                            }
                        }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                HStack {
                    Text("Right-click a link to open it again or copy it.")
                        .settingsFootnote()
                    Spacer()
                    Button("Clear History") {
                        model.clearLinkHistory()
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct HistoryRow: View {
    let entry: LinkHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.url.absoluteString)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var detailText: String {
        var parts = [entry.date.formatted(date: .abbreviated, time: .shortened)]
        if let sourceAppName = entry.sourceAppName {
            let bundleNote = entry.sourceAppBundleIdentifier.map { " (\($0))" } ?? ""
            parts.append("from \(sourceAppName)\(bundleNote)")
        }
        parts.append("opened in \(entry.destinationName)")
        parts.append(entry.reasonDescription)
        return parts.joined(separator: " · ")
    }
}
