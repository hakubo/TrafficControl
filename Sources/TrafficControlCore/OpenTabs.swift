import Foundation

/// Whether to switch to a tab that already shows the link instead of opening a new one.
public enum TabReuseMode: String, Codable, CaseIterable, Sendable, Hashable {
    case anyBrowser
    case targetBrowser
    case off

    public var label: String {
        switch self {
        case .anyBrowser: "Switch to it, in any running browser"
        case .targetBrowser: "Switch to it, only in the browser it would open in"
        case .off: "Open a new tab anyway"
        }
    }
}

/// Decides whether an open tab shows "the same page" as a clicked link.
public enum TabMatching {
    /// Query parameters that only track where a click came from.
    static let ignoredParameters: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_eid", "igshid", "si"]

    /// Ignores http vs https, "www.", a trailing slash, the fragment and tracking parameters.
    public static func key(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            var host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }

        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }

        let query = (components.percentEncodedQuery ?? "")
            .split(separator: "&")
            .filter { pair in
                let name = pair.split(separator: "=", maxSplits: 1).first.map { $0.lowercased() } ?? ""
                return !name.hasPrefix("utm_") && !ignoredParameters.contains(name)
            }
            .joined(separator: "&")

        let port = components.port.map { ":\($0)" } ?? ""
        return host + port + path + (query.isEmpty ? "" : "?" + query)
    }

    public static func same(_ a: URL, _ b: URL) -> Bool {
        guard let ka = key(for: a), let kb = key(for: b) else { return false }
        return ka == kb
    }

    /// The first window/tab (in the order given, front to back) showing `url`.
    public static func find<WindowID>(_ url: URL, in windows: [(id: WindowID, tabs: [String])]) -> (window: WindowID, tabIndex: Int)? {
        guard let wanted = key(for: url) else { return nil }
        for window in windows {
            for (index, tab) in window.tabs.enumerated() {
                if let tabURL = URL(string: tab), key(for: tabURL) == wanted {
                    return (window.id, index + 1)
                }
            }
        }
        return nil
    }
}
