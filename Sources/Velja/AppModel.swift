import AppKit
import Observation
import VeljaCore

/// Velja's shared state: settings, link history, and installed browsers. Settings and history are
/// saved to disk on every change.
@MainActor
@Observable
final class AppModel {
    var settings: VeljaSettings {
        didSet {
            guard settings != oldValue else {
                return
            }
            if oldValue.keepsLinkHistory, !settings.keepsLinkHistory {
                linkHistory.removeAllEntries()
            }
            saveSettings()
            onSettingsChanged?()
        }
    }

    private(set) var linkHistory: LinkHistory {
        didSet {
            saveLinkHistory()
        }
    }

    private(set) var installedBrowsers: [InstalledBrowser] = []
    private(set) var isVeljaDefaultBrowser = false
    /// Set when the settings file could not be read at launch. Shown in the settings window.
    private(set) var settingsLoadProblem: String?
    /// True when there was no settings file at launch, meaning this is the first launch.
    let isFirstLaunch: Bool

    /// Called after every settings change, for example to show or hide the menu bar icon.
    @ObservationIgnored var onSettingsChanged: (() -> Void)?

    @ObservationIgnored private let settingsStore: JSONFileStore<VeljaSettings>
    @ObservationIgnored private let linkHistoryStore: JSONFileStore<LinkHistory>

    /// True when an unreadable settings file could not be moved aside; saving would overwrite it.
    @ObservationIgnored private let isSettingsSavingBlocked: Bool

    /// Where Velja keeps Settings.json and History.json: `~/Library/Application Support/Velja`, or the
    /// absolute path in `VELJA_SUPPORT_DIRECTORY`. scripts/e2e.sh sets that variable to isolate test runs;
    /// normal launches through Launch Services never carry it.
    static var defaultSupportDirectory: URL {
        if let overridePath = ProcessInfo.processInfo.environment["VELJA_SUPPORT_DIRECTORY"], overridePath.hasPrefix("/") {
            return URL(filePath: overridePath, directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Velja", directoryHint: .isDirectory)
    }

    init(supportDirectory: URL = AppModel.defaultSupportDirectory) {
        settingsStore = JSONFileStore(fileURL: supportDirectory.appending(path: "Settings.json", directoryHint: .notDirectory))
        linkHistoryStore = JSONFileStore(fileURL: supportDirectory.appending(path: "History.json", directoryHint: .notDirectory))

        var loadProblem: String?
        switch settingsStore.loadJSONFile() {
        case .loaded(let loadedSettings):
            settings = loadedSettings
            isFirstLaunch = false
            isSettingsSavingBlocked = false
        case .missing:
            settings = VeljaSettings()
            isFirstLaunch = true
            isSettingsSavingBlocked = false
        case .unreadable(let errorDescription, let backupURL?):
            settings = VeljaSettings()
            isFirstLaunch = false
            isSettingsSavingBlocked = false
            loadProblem = "Velja could not read its settings file and started with default settings. The old file was moved to \(backupURL.path(percentEncoded: false))."
            VeljaLog.storage.error("Settings file unreadable: \(errorDescription, privacy: .public)")
        case .unreadable(let errorDescription, nil):
            settings = VeljaSettings()
            isFirstLaunch = false
            isSettingsSavingBlocked = true
            loadProblem = "Velja could not read its settings file and started with default settings; changes will not be saved until the file is fixed or removed."
            VeljaLog.storage.error("Settings file unreadable and could not be moved aside; settings will not be saved: \(errorDescription, privacy: .public)")
        }

        switch linkHistoryStore.loadJSONFile() {
        case .loaded(let loadedHistory):
            linkHistory = loadedHistory
        case .missing:
            linkHistory = LinkHistory()
        case .unreadable(let errorDescription, _):
            linkHistory = LinkHistory()
            VeljaLog.storage.error("History file unreadable: \(errorDescription, privacy: .public)")
        }
        settingsLoadProblem = loadProblem
        if isFirstLaunch {
            // Write the defaults now, so the next launch is not treated as the first one again.
            saveSettings()
        }
        if !settings.keepsLinkHistory, !linkHistory.entries.isEmpty {
            linkHistory.removeAllEntries()
        }

        refreshInstalledBrowsers()
        refreshDefaultBrowserStatus()
    }

    // MARK: Browsers

    /// Looks for installed browsers and profiles again. Cheap enough to call for every link.
    func refreshInstalledBrowsers() {
        installedBrowsers = BrowserCatalog.findInstalledBrowsers()
    }

    func refreshDefaultBrowserStatus() {
        isVeljaDefaultBrowser = DefaultBrowserSetting.isVeljaDefaultBrowser()
    }

    /// Every browser and profile that can open links, for routing. Includes profiles even when the
    /// picker does not list them, so rules pointing at a profile keep working.
    var availableBrowserTargets: Set<BrowserTarget> {
        var targets = Set<BrowserTarget>()
        for browser in installedBrowsers {
            targets.insert(BrowserTarget(bundleIdentifier: browser.bundleIdentifier))
            for profile in browser.profiles {
                targets.insert(BrowserTarget(bundleIdentifier: browser.bundleIdentifier, profileDirectory: profile.directoryName))
            }
        }
        return targets
    }

    /// Choices for settings pickers such as the primary browser: every browser, plus each profile
    /// of browsers with more than one profile.
    var selectableBrowserChoices: [BrowserChoice] {
        installedBrowsers.flatMap { browser -> [BrowserChoice] in
            let plainChoice = BrowserChoice(target: BrowserTarget(bundleIdentifier: browser.bundleIdentifier), browserName: browser.name, icon: browser.icon)
            guard browser.profiles.count > 1 else {
                return [plainChoice]
            }
            return [plainChoice] + profileChoices(for: browser)
        }
    }

    /// Every entry the browser picker can list, in picker order, including hidden ones.
    var orderedBrowserPickerChoices: [BrowserChoice] {
        let candidates = installedBrowsers.flatMap { browser -> [BrowserChoice] in
            if settings.showsBrowserProfiles, browser.profiles.count > 1 {
                return profileChoices(for: browser)
            }
            return [BrowserChoice(target: BrowserTarget(bundleIdentifier: browser.bundleIdentifier), browserName: browser.name, icon: browser.icon)]
        }
        let choicesByTarget = Dictionary(candidates.map { ($0.target, $0) }, uniquingKeysWith: { first, _ in first })
        return BrowserPickerOrdering.orderedBrowserTargets(available: candidates.map(\.target), savedOrder: settings.browserPickerOrder)
            .compactMap { choicesByTarget[$0] }
    }

    /// The entries the browser picker shows, in order.
    var visibleBrowserPickerChoices: [BrowserChoice] {
        let ordered = orderedBrowserPickerChoices
        let visibleTargets = Set(BrowserPickerOrdering.visibleBrowserTargets(
            available: ordered.map(\.target),
            savedOrder: [],
            hidden: settings.hiddenBrowserPickerTargets
        ))
        return ordered.filter { visibleTargets.contains($0.target) }
    }

    /// A display name for a browser target, even when it is no longer installed.
    func browserTitle(for target: BrowserTarget) -> String {
        if let choice = selectableBrowserChoices.first(where: { $0.target == target })
            ?? orderedBrowserPickerChoices.first(where: { $0.target == target }) {
            return choice.title
        }
        guard let browser = installedBrowsers.first(where: { $0.bundleIdentifier == target.bundleIdentifier }) else {
            return "\(target.bundleIdentifier) (not installed)"
        }
        if let profileDirectory = target.profileDirectory {
            let profileName = browser.profiles.first { $0.directoryName == profileDirectory }?.displayName
            return "\(browser.name) — \(profileName ?? "\(profileDirectory) (missing profile)")"
        }
        return browser.name
    }

    private func profileChoices(for browser: InstalledBrowser) -> [BrowserChoice] {
        browser.profiles.map { profile in
            BrowserChoice(
                target: BrowserTarget(bundleIdentifier: browser.bundleIdentifier, profileDirectory: profile.directoryName),
                browserName: browser.name,
                profileName: profile.displayName,
                icon: browser.icon
            )
        }
    }

    // MARK: Rules

    /// Adds a rule at the top of the list, so it wins over broader rules added earlier.
    func insertRuleAtTop(_ rule: LinkRule) {
        settings.rules.insert(rule, at: 0)
    }

    // MARK: History

    /// Records an opened link when link history is on.
    func recordOpenedLink(_ entry: LinkHistoryEntry) {
        guard settings.keepsLinkHistory else {
            return
        }
        linkHistory.recordOpenedLink(entry)
    }

    func clearLinkHistory() {
        linkHistory.removeAllEntries()
    }

    // MARK: Saving

    private func saveSettings() {
        guard !isSettingsSavingBlocked else {
            return
        }
        do {
            try settingsStore.saveJSONFile(settings)
        } catch {
            VeljaLog.storage.error("Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveLinkHistory() {
        do {
            try linkHistoryStore.saveJSONFile(linkHistory)
        } catch {
            VeljaLog.storage.error("Could not save link history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
