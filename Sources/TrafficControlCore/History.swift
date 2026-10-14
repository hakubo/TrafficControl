import Foundation

/// Where a link ended up.
public enum LinkDestination: Codable, Hashable, Sendable {
    case browser(BrowserTarget)
    case app(bundleID: String)
}

public struct DestinationTally: Codable, Hashable, Sendable {
    public var destination: LinkDestination
    public var count: Int
}

/// Visits to a domain or one of its paths, and where they went.
public protocol DestinationHistory {
    var visits: Int { get }
    var lastOpened: Date { get }
    var lastDestination: LinkDestination? { get }
    var destinations: [DestinationTally] { get }
}

extension DestinationHistory {
    /// The destination used most; the most recent one wins a tie.
    public var preferred: LinkDestination? {
        let best = destinations.map(\.count).max() ?? 0
        let tied = destinations.filter { $0.count == best }.map(\.destination)
        if let last = lastDestination, tied.contains(last) { return last }
        return tied.first
    }

    /// The preferred destination as a browser, which is what a rule can target.
    public var preferredBrowser: BrowserTarget? {
        if case .browser(let target) = preferred { return target }
        return destinations.sorted { $0.count > $1.count }.lazy.compactMap { tally -> BrowserTarget? in
            if case .browser(let target) = tally.destination { return target }
            return nil
        }.first
    }

}

public protocol TallyRecording: DestinationHistory {
    var visits: Int { get set }
    var lastOpened: Date { get set }
    var lastDestination: LinkDestination? { get set }
    var destinations: [DestinationTally] { get set }
}

extension TallyRecording {
    mutating func tally(_ destination: LinkDestination, at date: Date) {
        visits += 1
        lastOpened = date
        lastDestination = destination
        if let i = destinations.firstIndex(where: { $0.destination == destination }) {
            destinations[i].count += 1
        } else {
            destinations.append(DestinationTally(destination: destination, count: 1))
        }
    }
}

/// The first path segment of a domain's links, e.g. "hakubo" for github.com/hakubo/api.
public struct PathRecord: Codable, Identifiable, Hashable, Sendable, TallyRecording {
    public var id: String { segment }
    public let segment: String
    public var visits: Int
    public var lastOpened: Date
    public var lastDestination: LinkDestination?
    public var destinations: [DestinationTally]
}

public struct DomainRecord: Codable, Identifiable, Hashable, Sendable, TallyRecording {
    public var id: String { domain }
    public let domain: String
    public var visits: Int
    public var lastOpened: Date
    public var lastDestination: LinkDestination?
    public var destinations: [DestinationTally]
    /// Most visited first.
    public var paths: [PathRecord]

    /// Paths kept per domain; the least recently opened go first.
    public static let pathLimit = 30

    init(domain: String, date: Date) {
        self.domain = domain
        visits = 0
        lastOpened = date
        lastDestination = nil
        destinations = []
        paths = []
    }

    private enum CodingKeys: String, CodingKey {
        case domain, visits, lastOpened, lastDestination, destinations, paths
    }

    // `paths` arrived in 0.1.4; older history files don't have it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        domain = try c.decode(String.self, forKey: .domain)
        visits = try c.decode(Int.self, forKey: .visits)
        lastOpened = try c.decode(Date.self, forKey: .lastOpened)
        lastDestination = try c.decodeIfPresent(LinkDestination.self, forKey: .lastDestination)
        destinations = try c.decode([DestinationTally].self, forKey: .destinations)
        paths = try c.decodeIfPresent([PathRecord].self, forKey: .paths) ?? []
    }
}

/// Domains of opened links, with where each one went, so they can be turned into rules.
public struct LinkHistory: Codable, Equatable, Sendable {
    public private(set) var records: [String: DomainRecord] = [:]

    /// Oldest domains are dropped past this many.
    public static let limit = 500

    public init() {}

    /// The host without a leading "www.", for http(s) links only.
    public static func domain(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    public func record(for url: URL) -> DomainRecord? {
        Self.domain(for: url).flatMap { records[$0] }
    }

    /// What you usually pick for this link's path, falling back to its domain.
    public func preferred(for url: URL) -> LinkDestination? {
        guard let record = record(for: url) else { return nil }
        if let segment = Self.firstSegment(of: url),
           let path = record.paths.first(where: { $0.segment == segment }),
           let preferred = path.preferred {
            return preferred
        }
        return record.preferred
    }

    static func firstSegment(of url: URL) -> String? {
        LinkAddress.segments(of: url).first?.lowercased()
    }

    /// Most recently opened first.
    public var recent: [DomainRecord] {
        records.values.sorted { $0.lastOpened > $1.lastOpened }
    }

    public mutating func record(_ url: URL, destination: LinkDestination, at date: Date = Date()) {
        guard let domain = Self.domain(for: url) else { return }
        var entry = records[domain] ?? DomainRecord(domain: domain, date: date)
        entry.tally(destination, at: date)
        if let segment = Self.firstSegment(of: url) {
            if let i = entry.paths.firstIndex(where: { $0.segment == segment }) {
                entry.paths[i].tally(destination, at: date)
            } else {
                var path = PathRecord(segment: segment, visits: 0, lastOpened: date, lastDestination: nil, destinations: [])
                path.tally(destination, at: date)
                entry.paths.append(path)
            }
            if entry.paths.count > DomainRecord.pathLimit,
               let oldest = entry.paths.indices.min(by: { entry.paths[$0].lastOpened < entry.paths[$1].lastOpened }) {
                entry.paths.remove(at: oldest)
            }
            entry.paths.sort { $0.visits > $1.visits }
        }
        records[domain] = entry

        if records.count > Self.limit, let oldest = records.values.min(by: { $0.lastOpened < $1.lastOpened }) {
            records[oldest.domain] = nil
        }
    }

    public mutating func remove(_ domain: String) {
        records[domain] = nil
    }

    public mutating func clear() {
        records.removeAll()
    }
}

extension Rule {
    /// A rule for a domain or a path on it ("github.com", "github.com/buffer"), including subdomains
    /// and everything below the path.
    public static func forAddress(_ address: String, to target: BrowserTarget?) -> Rule {
        let address = LinkAddress.normalize(address)
        return Rule(
            name: address,
            conditions: [Condition(field: .address, op: .isUnder, value: address)],
            action: target.map { .open(browserID: $0.browserID, profileID: $0.profileID) } ?? .ask)
    }

    /// Where a new rule for `address` should go so it isn't hidden behind a broader rule:
    /// a path rule goes above the first existing rule that already catches its links; a domain rule goes last.
    public static func insertionIndex(for address: String, in rules: [Rule]) -> Int {
        let address = LinkAddress.normalize(address)
        guard address.contains("/"), let url = URL(string: "https://" + address) else { return rules.count }
        return rules.firstIndex { $0.matches(LinkContext(url: url)) } ?? rules.count
    }
}

public struct HistoryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        SettingsStore.defaultFileURL.deletingLastPathComponent().appending(path: "history.json")
    }

    public func load() -> LinkHistory {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? JSONDecoder().decode(LinkHistory.self, from: data)
        else { return LinkHistory() }
        return history
    }

    public func save(_ history: LinkHistory) throws {
        let data = try JSONEncoder().encode(history)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
