import Foundation

/// A browser profile, such as Chrome's "Work" profile stored in the `Profile 1` directory.
public struct BrowserProfile: Hashable, Sendable {
    /// Directory name passed to `--profile-directory`, for example `Default` or `Profile 1`.
    public var directoryName: String
    /// The name the user gave the profile in the browser.
    public var displayName: String

    public init(directoryName: String, displayName: String) {
        self.directoryName = directoryName
        self.displayName = displayName
    }
}

/// Finds Chromium browser profiles and builds the launch arguments that open a link in one.
public enum ChromiumProfileSupport {
    /// User data directories, relative to `~/Library/Application Support`, keyed by browser bundle identifier.
    /// Only browsers that honor `--profile-directory` are listed.
    static let userDataDirectoriesByBundleIdentifier: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.brave.Browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
        "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    /// Returns the `Local State` file that lists a browser's profiles, or `nil` for browsers without profile support.
    /// An entry in `userDataDirectoryOverrides` wins over the built-in table.
    public static func localStateFileURL(
        forBrowserBundleIdentifier bundleIdentifier: String,
        applicationSupportDirectory: URL,
        userDataDirectoryOverrides: [String: URL]
    ) -> URL? {
        let userDataDirectory: URL
        if let overrideDirectory = userDataDirectoryOverrides[bundleIdentifier] {
            userDataDirectory = overrideDirectory
        } else if let relativePath = userDataDirectoriesByBundleIdentifier[bundleIdentifier] {
            userDataDirectory = applicationSupportDirectory.appending(path: relativePath, directoryHint: .isDirectory)
        } else {
            return nil
        }
        return userDataDirectory.appending(path: "Local State", directoryHint: .notDirectory)
    }

    /// Parses the `VELJA_CHROMIUM_USER_DATA_DIRECTORIES` value, `bundle.id=/absolute/path;other.id=/path`, into
    /// extra Chromium-style user data directories by bundle identifier, for end-to-end tests with a fake browser
    /// and advanced use. Malformed entries and relative paths are skipped.
    public static func parseUserDataDirectoryOverrides(_ value: String) -> [String: URL] {
        var overrides: [String: URL] = [:]
        for entry in value.split(separator: ";") {
            guard let separatorIndex = entry.firstIndex(of: "=") else {
                continue
            }
            let bundleIdentifier = entry[..<separatorIndex].trimmingCharacters(in: .whitespaces)
            let path = entry[entry.index(after: separatorIndex)...].trimmingCharacters(in: .whitespaces)
            guard !bundleIdentifier.isEmpty, path.hasPrefix("/") else {
                continue
            }
            overrides[bundleIdentifier] = URL(filePath: path, directoryHint: .isDirectory)
        }
        return overrides
    }

    /// Reads the profiles listed in a Chromium `Local State` file, in the browser's own profile order.
    /// Returns an empty list when the file cannot be parsed.
    public static func parseLocalStateProfiles(_ localStateData: Data) -> [BrowserProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: localStateData) as? [String: Any],
              let profileSection = root["profile"] as? [String: Any],
              let infoCache = profileSection["info_cache"] as? [String: Any] else {
            return []
        }
        let ignoredDirectories: Set<String> = ["System Profile", "Guest Profile"]
        let directoryNames = infoCache.keys.filter { !ignoredDirectories.contains($0) }
        let savedOrder = (profileSection["profiles_order"] as? [String]) ?? []
        let orderedDirectoryNames = savedOrder.filter(directoryNames.contains)
            + directoryNames.filter { !savedOrder.contains($0) }.sorted(by: isOrderedBeforeInProfileList)

        var profiles = orderedDirectoryNames.map { directoryName -> BrowserProfile in
            let info = infoCache[directoryName] as? [String: Any]
            let name = (info?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return BrowserProfile(directoryName: directoryName, displayName: name.isEmpty ? directoryName : name)
        }
        // Two profiles can share a name; add the directory so picker entries stay distinguishable.
        let duplicateNames = Set(Dictionary(grouping: profiles, by: \.displayName).filter { $0.value.count > 1 }.keys)
        for index in profiles.indices where duplicateNames.contains(profiles[index].displayName) {
            profiles[index].displayName += " (\(profiles[index].directoryName))"
        }
        return profiles
    }

    /// Command-line arguments that open a link, or a new window when `url` is `nil`, in a profile.
    public static func launchArguments(profileDirectory: String, url: URL?) -> [String] {
        var arguments = ["--profile-directory=\(profileDirectory)"]
        if let url {
            arguments.append(url.absoluteString)
        }
        return arguments
    }

    /// Sorts `Default` first, then `Profile 2` before `Profile 10`.
    private static func isOrderedBeforeInProfileList(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "Default" { return rhs != "Default" }
        if rhs == "Default" { return false }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
