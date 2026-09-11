import Foundation

/// The file format for exporting and importing rules, so they can be backed up or moved to another Mac.
public struct RuleExportFile: Codable, Equatable, Sendable {
    /// Bumped when the format changes in a way older versions cannot read.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var rules: [LinkRule]

    public init(rules: [LinkRule]) {
        self.formatVersion = Self.currentFormatVersion
        self.rules = rules
    }

    /// Encodes rules for an export file.
    public static func encodeRuleExport(_ rules: [LinkRule]) throws -> Data {
        try JSONEncoder.veljaFileEncoder.encode(RuleExportFile(rules: rules))
    }

    /// Decodes an export file and gives every rule and matcher a fresh identifier, so importing the
    /// same file twice, or into the Mac it came from, never produces duplicate identifiers.
    public static func decodeRuleExport(_ data: Data) throws -> [LinkRule] {
        let file = try JSONDecoder.veljaFileDecoder.decode(RuleExportFile.self, from: data)
        guard file.formatVersion <= currentFormatVersion else {
            throw RuleExportError.unsupportedFormatVersion(file.formatVersion)
        }
        return file.rules.map { rule in
            var importedRule = rule
            importedRule.id = UUID()
            importedRule.urlMatchers = rule.urlMatchers.map { matcher in
                var importedMatcher = matcher
                importedMatcher.id = UUID()
                return importedMatcher
            }
            return importedRule
        }
    }
}

/// Errors from reading a rule export file.
public enum RuleExportError: Error, Equatable, LocalizedError {
    case unsupportedFormatVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            "Rule export format version \(version) is newer than this version of Velja supports."
        }
    }
}
