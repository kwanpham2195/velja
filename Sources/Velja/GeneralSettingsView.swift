import SwiftUI
import VeljaCore

/// General settings: default browser status, primary and alternative browser, link cleanup, and app options.
struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    @State private var isLaunchAtLoginEnabled = LaunchAtLogin.isLaunchAtLoginEnabled
    /// True while the login item is registered but not yet approved in System Settings.
    @State private var needsLoginItemApproval = LaunchAtLogin.needsLoginItemApproval
    /// The last login item error; kept until the next successful change.
    @State private var launchAtLoginMessage: String?
    @State private var defaultBrowserMessage: String?

    var body: some View {
        Form {
            if let settingsLoadProblem = model.settingsLoadProblem {
                Section {
                    Label(settingsLoadProblem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if model.isVeljaDefaultBrowser {
                    Label("Linkfork is your default browser.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Linkfork is not your default browser, so links do not reach it yet.", systemImage: "exclamationmark.circle")
                        Button("Set Linkfork as Default Browser…") {
                            makeVeljaDefaultBrowser()
                        }
                        if let defaultBrowserMessage {
                            Text(defaultBrowserMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Default Browser")
            }

            Section {
                BrowserSelectionPicker(title: "Primary browser", selection: $model.settings.primaryBrowser, model: model)
                BrowserSelectionPicker(title: "Alternative browser", selection: $model.settings.alternativeBrowser, model: model)
            } header: {
                Text("Opening Links")
            } footer: {
                Text("Links open in the primary browser unless an app link or rule applies. Hold Fn (Globe) while clicking a link to use the alternative browser instead, skipping app links and rules.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Remove tracking parameters", isOn: $model.settings.removesTrackingParameters)
                Toggle("Expand short links", isOn: $model.settings.expandsShortURLs)
            } header: {
                Text("Link Cleanup")
            } footer: {
                Text("Removing tracking parameters strips utm_source, fbclid, and similar parameters before a link opens. Expanding short links asks bit.ly, t.co, and similar link shorteners where a link leads, so rules match the real site. Only the link shortener receives a request; the destination site is not contacted.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Show menu bar icon", isOn: $model.settings.showsMenuBarIcon)
                Toggle("Launch at login", isOn: $isLaunchAtLoginEnabled)
                    .onChange(of: isLaunchAtLoginEnabled) { _, isEnabled in
                        setLaunchAtLogin(isEnabled)
                    }
                if needsLoginItemApproval {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Approve Linkfork in System Settings > General > Login Items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items Settings") {
                            LaunchAtLogin.openLoginItemsSettings()
                        }
                    }
                }
                if let launchAtLoginMessage {
                    Text(launchAtLoginMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Keep link history", isOn: $model.settings.keepsLinkHistory)
            } header: {
                Text("App")
            } footer: {
                Text("With the menu bar icon hidden, open Linkfork again from Finder or Spotlight to show this window. Link history stays on this Mac; turning it off deletes it.")
                    .settingsFootnote()
            }

            Section {
                LabeledContent("Version", value: Self.appVersion)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshLaunchAtLoginStatus()
            model.refreshDefaultBrowserStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have approved the login item in System Settings meanwhile.
            refreshLaunchAtLoginStatus()
        }
    }

    private func refreshLaunchAtLoginStatus() {
        isLaunchAtLoginEnabled = LaunchAtLogin.isLaunchAtLoginEnabled
        needsLoginItemApproval = LaunchAtLogin.needsLoginItemApproval
    }

    private func makeVeljaDefaultBrowser() {
        defaultBrowserMessage = nil
        Task {
            do {
                try await DefaultBrowserSetting.makeVeljaDefaultBrowser()
            } catch {
                defaultBrowserMessage = "The default browser was not changed. You can also choose Linkfork in System Settings > Desktop & Dock > Default web browser."
                VeljaLog.system.error("Default browser change declined or failed: \(error.localizedDescription, privacy: .public)")
            }
            model.refreshDefaultBrowserStatus()
        }
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        // Also reached when refreshLaunchAtLoginStatus() resets the toggle; keep any failure message.
        guard isEnabled != LaunchAtLogin.isLaunchAtLoginEnabled else {
            return
        }
        do {
            try LaunchAtLogin.setLaunchAtLoginEnabled(isEnabled)
            launchAtLoginMessage = nil
        } catch {
            launchAtLoginMessage = "Could not change the login item: \(error.localizedDescription)"
            VeljaLog.system.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshLaunchAtLoginStatus()
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "development build"
        let buildNumber = info?["CFBundleVersion"] as? String
        return buildNumber.map { "\(shortVersion) (\($0))" } ?? shortVersion
    }
}

extension View {
    /// Style for the explanatory text under a settings section.
    func settingsFootnote() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
