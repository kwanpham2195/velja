import Foundation
import Testing
@testable import VeljaCore

private func decodeSettings(_ json: String) throws -> VeljaSettings {
    try JSONDecoder.veljaFileDecoder.decode(VeljaSettings.self, from: Data(json.utf8))
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "VeljaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

struct VeljaSettingsDecodingTests {
    @Test func missingKeysUseDefaultsWithAppleMusicOff() throws {
        let decoded = try decodeSettings(#"{"showsMenuBarIcon": false}"#)
        var expected = VeljaSettings()
        expected.showsMenuBarIcon = false
        #expect(decoded == expected)
        #expect(!decoded.isNativeAppLinkHandlerEnabled(.appleMusic))
        for handler in NativeAppLinkHandler.allCases where handler != .appleMusic {
            #expect(decoded.isNativeAppLinkHandlerEnabled(handler))
        }
    }

    @Test func savedAppLinkHandlerListWinsAndUnknownNamesAreKept() throws {
        let decoded = try decodeSettings(#"{"disabledNativeAppLinkHandlers": ["zoom", "futureApp"]}"#)
        #expect(!decoded.isNativeAppLinkHandlerEnabled(.zoom))
        #expect(decoded.isNativeAppLinkHandlerEnabled(.figma))
        #expect(decoded.isNativeAppLinkHandlerEnabled(.appleMusic))
        #expect(decoded.disabledNativeAppLinkHandlers.contains("futureApp"))
    }
}

struct JSONFileStoreTests {
    @Test func unreadableFileIsMovedAsideAndNotOverwritten() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "Settings.json")
        try Data("{ broken".utf8).write(to: fileURL)
        let store = JSONFileStore<VeljaSettings>(fileURL: fileURL)

        guard case .unreadable(_, let backupURL?) = store.loadJSONFile() else {
            Issue.record("Expected an unreadable file with a backup")
            return
        }
        try store.saveJSONFile(VeljaSettings())
        #expect(backupURL.lastPathComponent.hasPrefix("Settings.unreadable-"))
        #expect(try String(contentsOf: backupURL, encoding: .utf8) == "{ broken")
    }

    @Test func savingThroughSymlinkKeepsTheSymlink() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dotfileURL = directory.appending(path: "dotfiles/velja.json")
        try FileManager.default.createDirectory(at: dotfileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dotfileURL)
        let settingsURL = directory.appending(path: "Settings.json")
        try FileManager.default.createSymbolicLink(at: settingsURL, withDestinationURL: dotfileURL)

        let settings = VeljaSettings(removesTrackingParameters: true)
        try JSONFileStore<VeljaSettings>(fileURL: settingsURL).saveJSONFile(settings)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: settingsURL.path) == dotfileURL.path)
        #expect(try decodeSettings(String(contentsOf: dotfileURL, encoding: .utf8)) == settings)
    }
}

struct ChromiumUserDataOverrideTests {
    @Test func overridesKeepAbsolutePathsAndSkipMalformedEntries() {
        let overrides = ChromiumProfileSupport.parseUserDataDirectoryOverrides(
            "com.example.Fake=/tmp/fake user data;no-separator;=/tmp/no-id;com.example.Relative=relative/path;com.example.Other=/opt/a=b"
        )
        #expect(overrides.keys.sorted() == ["com.example.Fake", "com.example.Other"])
        #expect(overrides["com.example.Other"]?.path(percentEncoded: false) == "/opt/a=b/")
        let localStateURL = ChromiumProfileSupport.localStateFileURL(
            forBrowserBundleIdentifier: "com.example.Fake",
            applicationSupportDirectory: URL(filePath: "/unused", directoryHint: .isDirectory),
            userDataDirectoryOverrides: overrides
        )
        #expect(localStateURL?.path(percentEncoded: false) == "/tmp/fake user data/Local State")
    }
}
