import Foundation

/// When to send a web link to the matching desktop app instead of a browser.
public enum AppLinkMode: String, Codable, CaseIterable, Sendable, Hashable {
    case whenRunning
    case whenInstalled
    case never

    public var label: String {
        switch self {
        case .whenRunning: "When the app is running"
        case .whenInstalled: "Whenever the app is installed"
        case .never: "Never"
        }
    }
}

/// A desktop app that can open some web links itself, and how to turn such a link into its deep link.
public struct AppLink: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let summary: String
    /// Returns the deep link for URLs this app handles, nil otherwise.
    public let deepLink: @Sendable (URL) -> URL?
}

extension AppLink {
    public static let all: [AppLink] = [linear, notion, zoom, spotify]

    public static func first(for url: URL) -> (AppLink, URL)? {
        for app in all {
            if let link = app.deepLink(url) { return (app, link) }
        }
        return nil
    }

    /// linear://<path> is what Linear's own "open in desktop app" uses; the app maps it back to https://linear.app/<path>.
    public static let linear = AppLink(
        id: "linear", name: "Linear", bundleID: "com.linear",
        summary: "Issues, projects, views and documents on linear.app"
    ) { url in
        guard let parts = webParts(url, hosts: ["linear.app"]) else { return nil }
        // Only workspace pages; marketing pages such as /pricing or /changelog stay in the browser.
        let segments = parts.path.split(separator: "/")
        let workspacePages: Set<Substring> = [
            "issue", "project", "projects", "view", "views", "team", "initiative", "initiatives",
            "document", "cycle", "roadmap", "inbox", "my-issues", "settings", "customer", "customers", "review", "reviews",
        ]
        guard segments.count >= 2, workspacePages.contains(segments[1]) else { return nil }
        return URL(string: "linear://" + parts.path.dropFirst() + parts.suffix)
    }

    public static let notion = AppLink(
        id: "notion", name: "Notion", bundleID: "notion.id",
        summary: "Pages and databases on notion.so"
    ) { url in
        guard let parts = webParts(url, hosts: ["notion.so", "www.notion.so"]),
              parts.path.range(of: "[0-9a-f]{32}$", options: .regularExpression) != nil
        else { return nil }
        return URL(string: "notion://www.notion.so" + parts.path + parts.suffix)
    }

    public static let zoom = AppLink(
        id: "zoom", name: "Zoom", bundleID: "us.zoom.xos",
        summary: "Meeting links (zoom.us/j/…)"
    ) { url in
        guard let host = url.host()?.lowercased(), host == "zoom.us" || host.hasSuffix(".zoom.us"),
              let match = url.path().firstMatch(of: #/^\/j\/(\d+)/#)
        else { return nil }
        var components = URLComponents(string: "zoommtg://zoom.us/join")!
        components.queryItems = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: String(match.1))]
        if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value {
            components.queryItems?.append(URLQueryItem(name: "pwd", value: pwd))
        }
        return components.url
    }

    public static let spotify = AppLink(
        id: "spotify", name: "Spotify", bundleID: "com.spotify.client",
        summary: "Tracks, albums, artists, playlists and podcasts"
    ) { url in
        guard url.host()?.lowercased() == "open.spotify.com",
              let match = url.path().firstMatch(of: #/^(?:\/intl-[a-z-]+)?\/(track|album|artist|playlist|episode|show)\/([A-Za-z0-9]+)/#)
        else { return nil }
        return URL(string: "spotify:\(match.1):\(match.2)")
    }

    /// The percent-encoded path, plus "?query#fragment" as they appeared, for http(s) links on one of `hosts`.
    private static func webParts(_ url: URL, hosts: Set<String>) -> (path: String, suffix: String)? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), hosts.contains(host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        var suffix = ""
        if let query = components.percentEncodedQuery { suffix += "?" + query }
        if let fragment = components.percentEncodedFragment { suffix += "#" + fragment }
        return (components.percentEncodedPath, suffix)
    }
}
