import AppKit
import SwiftUI
import VeljaCore

/// App link settings: which desktop apps take their own links, such as Zoom meeting links.
struct AppLinksSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(NativeAppLinkHandler.allCases, id: \.self) { handler in
                    let installedAppURL = Self.installedAppURL(for: handler)
                    Toggle(isOn: enabledBinding(for: handler)) {
                        HStack(spacing: 10) {
                            if let installedAppURL {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: installedAppURL.path(percentEncoded: false)))
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "app.dashed")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(handler.displayName)
                                Text(installedAppURL == nil ? "\(handler.handledLinksDescription) · App not installed" : handler.handledLinksDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Open Links in Apps")
            } footer: {
                Text("App links are checked before rules and only apply when the app is installed. Hold Fn (Globe) while clicking to open one in the alternative browser instead.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    private func enabledBinding(for handler: NativeAppLinkHandler) -> Binding<Bool> {
        Binding(
            get: { model.settings.isNativeAppLinkHandlerEnabled(handler) },
            set: { model.settings.setNativeAppLinkHandler(handler, isEnabled: $0) }
        )
    }

    private static func installedAppURL(for handler: NativeAppLinkHandler) -> URL? {
        handler.appBundleIdentifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }
}
