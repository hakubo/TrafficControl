import Foundation

/// Everything known about a link at the moment it is clicked.
public struct LinkContext: Sendable, Equatable {
    public var url: URL
    public var sourceBundleID: String?
    public var sourceAppName: String?

    public init(url: URL, sourceBundleID: String? = nil, sourceAppName: String? = nil) {
        self.url = url
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
    }
}

public enum ConditionField: String, Codable, CaseIterable, Sendable, Hashable {
    case host
    case url
    case path
    case sourceApp

    public var label: String {
        switch self {
        case .host: "Domain"
        case .url: "Full URL"
        case .path: "Path"
        case .sourceApp: "Source app"
        }
    }

    /// Operators that make sense for this field, the first one being the default.
    public var operators: [ConditionOperator] {
        switch self {
        case .host: [.isDomain, .equals, .contains, .beginsWith, .endsWith, .wildcard, .regex]
        case .sourceApp: [.equals, .contains, .beginsWith, .wildcard, .regex]
        case .url, .path: [.contains, .equals, .beginsWith, .endsWith, .wildcard, .regex]
        }
    }

    public var placeholder: String {
        switch self {
        case .host: "github.com"
        case .url: "https://example.com/*"
        case .path: "/meeting"
        case .sourceApp: "com.tinyspeck.slackmacgap or Slack"
        }
    }
}

public enum ConditionOperator: String, Codable, CaseIterable, Sendable, Hashable {
    case isDomain
    case equals
    case contains
    case beginsWith
    case endsWith
    case wildcard
    case regex

    public var label: String {
        switch self {
        case .isDomain: "is or is under"
        case .equals: "is"
        case .contains: "contains"
        case .beginsWith: "begins with"
        case .endsWith: "ends with"
        case .wildcard: "matches wildcard"
        case .regex: "matches regex"
        }
    }

    /// Text comparisons are case-insensitive; regexes are compiled case-insensitively too.
    public func evaluate(_ subject: String, pattern: String) -> Bool {
        let s = subject.lowercased()
        let p = pattern.lowercased()
        switch self {
        case .equals:
            return s == p
        case .contains:
            return s.contains(p)
        case .beginsWith:
            return s.hasPrefix(p)
        case .endsWith:
            return s.hasSuffix(p)
        case .isDomain:
            let domain = p.hasPrefix(".") ? String(p.dropFirst()) : p
            return s == domain || s.hasSuffix("." + domain)
        case .wildcard:
            return Self.matches(s, regex: Self.wildcardToRegex(p))
        case .regex:
            return Self.matches(subject, regex: pattern)
        }
    }

    static func wildcardToRegex(_ wildcard: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: wildcard)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return "^" + escaped + "$"
    }

    static func matches(_ subject: String, regex pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(subject.startIndex..., in: subject)
        return regex.firstMatch(in: subject, range: range) != nil
    }
}

public struct Condition: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var field: ConditionField
    public var op: ConditionOperator
    public var value: String

    public init(id: UUID = UUID(), field: ConditionField = .host, op: ConditionOperator? = nil, value: String = "") {
        self.id = id
        self.field = field
        self.op = op ?? field.operators[0]
        self.value = value
    }

    public func matches(_ context: LinkContext) -> Bool {
        let pattern = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }
        let subjects: [String]
        switch field {
        case .url: subjects = [context.url.absoluteString]
        case .host: subjects = [context.url.host() ?? ""]
        case .path: subjects = [context.url.path(percentEncoded: false)]
        case .sourceApp: subjects = [context.sourceBundleID, context.sourceAppName].compactMap { $0 }
        }
        return subjects.contains { op.evaluate($0, pattern: pattern) }
    }
}

public enum MatchMode: String, Codable, CaseIterable, Sendable, Hashable {
    case all
    case any
}

public enum RuleAction: Codable, Equatable, Hashable, Sendable {
    /// Open the link in the browser with this bundle identifier, optionally in a specific profile.
    case open(browserID: String, profileID: String? = nil)
    /// Show the picker even if the default behavior would pick a browser.
    case ask
}

public struct Rule: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var matchMode: MatchMode
    public var conditions: [Condition]
    public var action: RuleAction

    public init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        matchMode: MatchMode = .all,
        conditions: [Condition] = [Condition()],
        action: RuleAction = .ask
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.matchMode = matchMode
        self.conditions = conditions
        self.action = action
    }

    /// A rule with no usable conditions never matches, so a half-written rule can't swallow every link.
    public func matches(_ context: LinkContext) -> Bool {
        guard isEnabled, !conditions.isEmpty else { return false }
        switch matchMode {
        case .all: return conditions.allSatisfy { $0.matches(context) }
        case .any: return conditions.contains { $0.matches(context) }
        }
    }
}
