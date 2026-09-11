import Foundation

/// One opened link in the link history.
public struct LinkHistoryEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    /// The link as it was opened, after short link expansion and tracking parameter removal.
    public var url: URL
    public var sourceAppBundleIdentifier: String?
    public var sourceAppName: String?
    /// Where the link went, for example "Google Chrome — Work" or "Zoom".
    public var destinationName: String
    /// Why it went there, for example "Rule: Work links".
    public var reasonDescription: String

    public init(
        id: UUID = UUID(),
        date: Date,
        url: URL,
        sourceAppBundleIdentifier: String?,
        sourceAppName: String?,
        destinationName: String,
        reasonDescription: String
    ) {
        self.id = id
        self.date = date
        self.url = url
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppName = sourceAppName
        self.destinationName = destinationName
        self.reasonDescription = reasonDescription
    }
}

/// The most recently opened links, newest first, stored in `~/Library/Application Support/Velja/History.json`.
public struct LinkHistory: Codable, Equatable, Sendable {
    /// Older entries are dropped once the history holds this many.
    public static let maximumEntryCount = 200

    public private(set) var entries: [LinkHistoryEntry]

    public init(entries: [LinkHistoryEntry] = []) {
        self.entries = Array(entries.prefix(Self.maximumEntryCount))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEntries = try container.decodeIfPresent([LinkHistoryEntry].self, forKey: .entries) ?? []
        entries = Array(decodedEntries.prefix(Self.maximumEntryCount))
    }

    /// Adds an entry at the top and drops the oldest entries beyond ``maximumEntryCount``.
    public mutating func recordOpenedLink(_ entry: LinkHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maximumEntryCount {
            entries.removeLast(entries.count - Self.maximumEntryCount)
        }
    }

    public mutating func removeAllEntries() {
        entries.removeAll()
    }
}
