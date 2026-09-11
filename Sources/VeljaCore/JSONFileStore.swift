import Foundation

/// The result of reading a JSON file from disk.
public enum JSONFileLoadResult<Value: Sendable>: Sendable {
    case loaded(Value)
    /// There is no file yet, for example on first launch.
    case missing
    /// The file exists but could not be read or decoded. It was moved to `backupURL` (when the move
    /// worked) so it is not overwritten, and the caller should continue with defaults.
    case unreadable(errorDescription: String, backupURL: URL?)
}

/// Reads and writes one Codable value as a pretty-printed JSON file, such as Velja's settings.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Reads the file. A file that fails to decode is renamed to `<name>.unreadable-<timestamp>.json`.
    public func loadJSONFile() -> JSONFileLoadResult<Value> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return .missing
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return .loaded(try JSONDecoder.veljaFileDecoder.decode(Value.self, from: data))
        } catch {
            let backupURL = moveUnreadableFileAside()
            return .unreadable(errorDescription: String(describing: error), backupURL: backupURL)
        }
    }

    /// Writes the value atomically to the file a symlink points to, so a symlinked settings file from a
    /// dotfile manager stays a symlink. Creates the parent directory when needed.
    public func saveJSONFile(_ value: Value) throws {
        let destinationURL = fileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.veljaFileEncoder.encode(value)
        try data.write(to: destinationURL, options: [.atomic])
    }

    private func moveUnreadableFileAside() -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let backupURL = fileURL.deletingLastPathComponent()
            .appending(path: "\(baseName).unreadable-\(formatter.string(from: Date())).json", directoryHint: .notDirectory)
        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }
}

extension JSONEncoder {
    /// Encoder for Velja's settings, history, and rule export files: readable, stable key order, ISO 8601 dates.
    public static var veljaFileEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    /// Decoder matching ``JSONEncoder/veljaFileEncoder``.
    public static var veljaFileDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
