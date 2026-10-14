import Foundation

/// A modifier key held while clicking a link.
public enum ModifierKey: String, Codable, CaseIterable, Sendable, Hashable {
    // In the order macOS writes them: ⌃⌥⇧⌘.
    case control, option, shift, command

    public var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    public var name: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        }
    }

    /// "⌥⌘" for [.command, .option].
    public static func symbols(_ keys: Set<ModifierKey>) -> String {
        allCases.filter(keys.contains).map(\.symbol).joined()
    }

    /// The keys named in a string of symbols such as "⌥⌘"; anything else is ignored.
    public static func parse(_ symbols: String) -> Set<ModifierKey> {
        Set(allCases.filter { symbols.contains($0.symbol) })
    }
}

/// Everything known about a link at the moment it is clicked.
public struct LinkContext: Sendable, Equatable {
    public var url: URL
    public var sourceBundleID: String?
    public var sourceAppName: String?
    /// Modifier keys held when the link was clicked.
    public var modifiers: Set<ModifierKey>

    public init(url: URL, sourceBundleID: String? = nil, sourceAppName: String? = nil, modifiers: Set<ModifierKey> = []) {
        self.url = url
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.modifiers = modifiers
    }
}

public enum ConditionField: String, Codable, CaseIterable, Sendable, Hashable {
    /// Domain plus path, e.g. "github.com/hakubo". Only in rules saved by 0.1.4: those load as a
    /// Domain condition plus a Path condition, and new rules can't pick it.
    case address
    case host
    case url
    case path
    case sourceApp
    /// Modifier keys held while clicking; the value is their symbols, e.g. "⌘" or "⌥⇧".
    case modifiers

    /// The fields offered when editing a condition.
    public static let selectable: [ConditionField] = [.host, .path, .url, .sourceApp, .modifiers]

    public var label: String {
        switch self {
        case .address: "Link"
        case .host: "Domain"
        case .url: "Full URL"
        case .path: "Path"
        case .sourceApp: "Source app"
        case .modifiers: "Keys held"
        }
    }

    /// Operators that make sense for this field, the first one being the default.
    public var operators: [ConditionOperator] {
        switch self {
        case .address: [.isUnder, .beginsWith, .equals, .contains, .wildcard, .regex]
        case .host: [.isDomain, .equals, .contains, .beginsWith, .endsWith, .wildcard, .regex]
        case .path: [.isUnder, .equals, .beginsWith, .contains, .endsWith, .wildcard, .regex]
        case .sourceApp: [.equals, .contains, .beginsWith, .wildcard, .regex]
        case .url: [.contains, .equals, .beginsWith, .endsWith, .wildcard, .regex]
        case .modifiers: [.includeKeys, .exactKeys]
        }
    }

    public var placeholder: String {
        switch self {
        case .address: "github.com/hakubo"
        case .host: "github.com"
        case .url: "https://example.com/*"
        case .path: "/buffer"
        case .sourceApp: "com.tinyspeck.slackmacgap or Slack"
        case .modifiers: "⌘"
        }
    }
}

public enum ConditionOperator: String, Codable, CaseIterable, Sendable, Hashable {
    /// The address or path itself, or anything below it: "github.com/buffer" matches
    /// "github.com/buffer/api" and "eu.github.com/buffer", not "github.com/buffer-x".
    case isUnder
    case isDomain
    case equals
    case contains
    case beginsWith
    case endsWith
    case wildcard
    case regex
    /// Keys held include all of these (others may be held too).
    case includeKeys
    /// Exactly these keys are held.
    case exactKeys

    public var label: String {
        switch self {
        case .isDomain: "is, including subdomains"
        case .isUnder: "is, including sub-paths"
        case .equals: "is"
        case .contains: "contains"
        case .beginsWith: "begins with"
        case .endsWith: "ends with"
        case .wildcard: "matches wildcard"
        case .regex: "matches regex"
        case .includeKeys: "include"
        case .exactKeys: "are exactly"
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
        case .isUnder:
            let (subjectHost, subjectPath) = Self.split(s)
            let (host, path) = Self.split(LinkAddress.normalize(p))
            let hostMatches = host.isEmpty || subjectHost == host || subjectHost.hasSuffix("." + host)
            let pathMatches = path.isEmpty || subjectPath == path || subjectPath.hasPrefix(path + "/")
            return hostMatches && pathMatches
        case .wildcard:
            return Self.matches(s, regex: Self.wildcardToRegex(p))
        case .regex:
            return Self.matches(subject, regex: pattern)
        case .includeKeys, .exactKeys:
            // Keys are matched in Condition.matches, which has the set of held keys.
            return false
        }
    }

    /// "github.com/buffer/api" → ("github.com", "/buffer/api"); "/buffer" → ("", "/buffer").
    static func split(_ address: String) -> (host: String, path: String) {
        guard let slash = address.firstIndex(of: "/") else { return (address, "") }
        return (String(address[..<slash]), String(address[slash...]))
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

/// A link written without its scheme: host (minus "www.") plus path, e.g. "github.com/hakubo/api".
public enum LinkAddress {
    /// The whole address of an http(s) link, or nil for other schemes.
    public static func of(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host + url.path(percentEncoded: false)
    }

    /// The domain plus up to `depth` path segments: depth 1 of github.com/hakubo/api is "github.com/hakubo".
    public static func of(_ url: URL, depth: Int) -> String? {
        guard let address = of(url) else { return nil }
        let parts = address.split(separator: "/", omittingEmptySubsequences: true)
        return parts.prefix(depth + 1).joined(separator: "/")
    }

    /// The path segments of a link, e.g. ["hakubo", "api"].
    public static func segments(of url: URL) -> [String] {
        url.path(percentEncoded: false).split(separator: "/").map(String.init)
    }

    /// Accepts what people paste: drops the scheme, "www.", a trailing slash, query and fragment.
    public static func normalize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let cut = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s == "/" ? "" : s
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
        var pattern = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }
        if field == .modifiers {
            let wanted = ModifierKey.parse(pattern)
            guard !wanted.isEmpty else { return false }
            return op == .exactKeys ? context.modifiers == wanted : wanted.isSubset(of: context.modifiers)
        }
        if field == .path, op == .isUnder, !pattern.hasPrefix("/") { pattern = "/" + pattern }
        let subjects: [String]
        switch field {
        case .url: subjects = [context.url.absoluteString]
        case .address: subjects = [LinkAddress.of(context.url)].compactMap { $0 }
        case .host: subjects = [context.url.host() ?? ""]
        case .path: subjects = [context.url.path(percentEncoded: false)]
        case .sourceApp: subjects = [context.sourceBundleID, context.sourceAppName].compactMap { $0 }
        case .modifiers: subjects = []
        }
        return subjects.contains { op.evaluate($0, pattern: pattern) }
    }
}

extension Condition {
    /// A 0.1.4 Link condition ("github.com/buffer", is or is under) as the equivalent Domain and Path
    /// conditions; nil for anything else.
    func splitIntoDomainAndPath() -> [Condition]? {
        guard field == .address, op == .isUnder else { return nil }
        let (host, path) = ConditionOperator.split(LinkAddress.normalize(value))
        guard !host.isEmpty else { return nil }
        var parts = [Condition(id: id, field: .host, op: .isDomain, value: host)]
        if !path.isEmpty { parts.append(Condition(field: .path, op: .isUnder, value: path)) }
        return parts
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

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, matchMode, conditions, action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        matchMode = try c.decode(MatchMode.self, forKey: .matchMode)
        action = try c.decode(RuleAction.self, forKey: .action)
        let saved = try c.decode([Condition].self, forKey: .conditions)
        // Splitting one condition into two only means the same thing when all of them must match.
        conditions = matchMode == .all || saved.count == 1
            ? saved.flatMap { $0.splitIntoDomainAndPath() ?? [$0] }
            : saved
        if saved.count == 1, conditions.count > 1 { matchMode = .all }
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
