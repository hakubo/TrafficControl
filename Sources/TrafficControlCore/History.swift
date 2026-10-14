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

public struct DomainRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String { domain }
    public let domain: String
    public var visits: Int
    public var lastOpened: Date
    public var lastDestination: LinkDestination?
    public var destinations: [DestinationTally]

    /// The destination used most for this domain; the most recent one wins a tie.
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

    /// Most recently opened first.
    public var recent: [DomainRecord] {
        records.values.sorted { $0.lastOpened > $1.lastOpened }
    }

    public mutating func record(_ url: URL, destination: LinkDestination, at date: Date = Date()) {
        guard let domain = Self.domain(for: url) else { return }
        var entry = records[domain] ?? DomainRecord(
            domain: domain, visits: 0, lastOpened: date, lastDestination: nil, destinations: [])
        entry.visits += 1
        entry.lastOpened = date
        entry.lastDestination = destination
        if let i = entry.destinations.firstIndex(where: { $0.destination == destination }) {
            entry.destinations[i].count += 1
        } else {
            entry.destinations.append(DestinationTally(destination: destination, count: 1))
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
    /// A rule that sends a domain and its subdomains to a browser.
    public static func forDomain(_ domain: String, to target: BrowserTarget?) -> Rule {
        Rule(
            name: domain,
            conditions: [Condition(field: .host, op: .isDomain, value: domain)],
            action: target.map { .open(browserID: $0.browserID, profileID: $0.profileID) } ?? .ask)
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
