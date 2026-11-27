import Foundation

/// When to send a web link to the matching desktop app instead of a browser.
public enum AppLinkMode: String, Codable, CaseIterable, Sendable, Hashable {
    case whenInstalled
    case whenRunning
    case never

    public var label: String {
        switch self {
        case .whenInstalled: "Open always"
        case .whenRunning: "Open only if app is open"
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
    /// Returns the deep link for URLs this app handles, nil otherwise. Settings carry per-app
    /// configuration, such as the Slack workspace IDs.
    let resolve: @Sendable (URL, AppSettings) -> URL?

    init(id: String, name: String, bundleID: String, summary: String, resolve: @escaping @Sendable (URL, AppSettings) -> URL?) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.summary = summary
        self.resolve = resolve
    }

    init(id: String, name: String, bundleID: String, summary: String, deepLink: @escaping @Sendable (URL) -> URL?) {
        self.init(id: id, name: name, bundleID: bundleID, summary: summary) { url, _ in deepLink(url) }
    }

    public func deepLink(_ url: URL, settings: AppSettings = AppSettings()) -> URL? {
        resolve(url, settings)
    }
}

extension AppLink {
    public static let all: [AppLink] = [linear, notion, figma, zoom, spotify, slack]

    public static func first(for url: URL, settings: AppSettings) -> (AppLink, URL)? {
        for app in all {
            if let link = app.deepLink(url, settings: settings) { return (app, link) }
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

    /// The app rewrites figma://<path> to https://www.figma.com/<path>, and drops links it can't show,
    /// so only file links go there; the file browser, community and image exports stay in the browser.
    public static let figma = AppLink(
        id: "figma", name: "Figma", bundleID: "com.figma.Desktop",
        summary: "Design, FigJam, Slides, Sites and Make files, prototypes and decks"
    ) { url in
        guard let parts = webParts(url, hosts: ["figma.com", "www.figma.com"]),
            parts.path.firstMatch(of: #/^\/(file|design|board|slides|site|buzz|make|proto|deck)\/[0-9a-zA-Z]{22,128}(\/|$)/#) != nil,
            !parts.path.contains("/image/"), !parts.suffix.contains("openInBrowser")
        else { return nil }
        return URL(string: "figma://" + parts.path.dropFirst() + parts.suffix)
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

    /// Slack only opens slack:// links, and those need the workspace's team ID. app.slack.com/client
    /// links carry it; <workspace>.slack.com permalinks don't, so `AppSettings.slackWorkspaces` maps
    /// the subdomain to it (TrafficControl looks it up the first time, see `SlackLink.workspaceToLearn`).
    /// Workspaces without an entry stay in the browser.
    public static let slack = AppLink(
        id: "slack", name: "Slack", bundleID: "com.tinyspeck.slackmacgap",
        summary: "Channels, messages, threads, files, lists and canvases on <workspace>.slack.com"
    ) { url, settings in
        guard let link = SlackLink(url) else { return nil }
        let team: String
        switch link.workspace {
        case .teamID(let id): team = id
        case .subdomain(let name):
            guard let id = settings.slackTeamID(forWorkspace: name) else { return nil }
            team = id
        }
        var components = URLComponents()
        components.scheme = "slack"
        let teamItem = URLQueryItem(name: "team", value: team)
        switch link.target {
        case .channel(let channel, let message, let thread):
            components.host = "channel"
            components.queryItems = [teamItem, URLQueryItem(name: "id", value: channel)]
            if let message { components.queryItems?.append(URLQueryItem(name: "message", value: message)) }
            if let thread { components.queryItems?.append(URLQueryItem(name: "thread_ts", value: thread)) }
        case .file(let id):
            components.host = "file"
            components.queryItems = [teamItem, URLQueryItem(name: "id", value: id)]
        case .list(let id):
            components.host = "list"
            components.queryItems = [teamItem, URLQueryItem(name: "id", value: id)]
        case .canvas(let id):
            // What Slack itself uses to hand a canvas over to the desktop app.
            components.host = "doc"
            components.queryItems = [teamItem, URLQueryItem(name: "id", value: id)]
        case .files:
            components.host = "files"
            components.queryItems = [teamItem]
        }
        return components.url
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

/// A Slack channel, message or thread link from the web.
public struct SlackLink: Equatable, Sendable {
    public enum Workspace: Equatable, Sendable {
        /// "acme" for acme.slack.com.
        case subdomain(String)
        /// From an app.slack.com/client/<team>/… link.
        case teamID(String)
    }

    public enum Target: Equatable, Sendable {
        /// A channel, or a message in it; timestamps look like "1700000100.654321".
        case channel(String, message: String?, thread: String?)
        /// One file, by its F… ID.
        case file(String)
        /// A list, by its F… ID.
        case list(String)
        /// A canvas, by its F… ID.
        case canvas(String)
        /// Any other page under /files.
        case files
    }

    public let workspace: Workspace
    public let target: Target

    public init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = url.host()?.lowercased(), host.hasSuffix(".slack.com")
        else { return nil }
        let path = url.path()
        if host == "app.slack.com" {
            // app.slack.com/client/T…/C…[/thread/C…-1700000000.123456]
            guard let match = path.firstMatch(of: #/^\/client\/([TE][A-Z0-9]+)\/([CGD][A-Z0-9]+)(?:\/thread\/[CGD][A-Z0-9]+-(\d+\.\d+))?\/?$/#)
            else { return nil }
            workspace = .teamID(String(match.1))
            let message = match.3.map(String.init)
            target = .channel(String(match.2), message: message, thread: message)
            return
        }
        let subdomain = String(host.dropLast(".slack.com".count))
        guard subdomain != "app", !subdomain.isEmpty else { return nil }
        // <workspace>.slack.com/lists/T…/F… and /docs/T…/F… carry the team ID themselves.
        if let match = path.firstMatch(of: #/^\/(lists|docs)\/([TE][A-Z0-9]+)\/(F[A-Z0-9]+)(?:\/|$)/#) {
            workspace = .teamID(String(match.2))
            target = match.1 == "lists" ? .list(String(match.3)) : .canvas(String(match.3))
            return
        }
        if let match = path.firstMatch(of: #/^\/archives\/([CGD][A-Z0-9]+)(?:\/p(\d{7,}))?\/?$/#) {
            // p1700000100654321 is the message timestamp 1700000100.654321 without its dot.
            let message = match.2.map { String($0.dropLast(6) + "." + $0.suffix(6)) }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let thread =
                message == nil
                ? nil
                : query.first(where: { $0.name == "thread_ts" })?.value.flatMap { $0.wholeMatch(of: #/\d+\.\d+/#) != nil ? $0 : nil }
            target = .channel(String(match.1), message: message, thread: thread)
        } else if let match = path.firstMatch(of: #/^\/files\/[UW][A-Z0-9]+\/(F[A-Z0-9]+)(?:\/|$)/#) {
            target = .file(String(match.1))
        } else if path == "/files" || path.hasPrefix("/files/") {
            target = .files
        } else {
            return nil
        }
        workspace = .subdomain(subdomain)
    }

    /// The subdomain whose team ID TrafficControl should look up before routing `url`, if any.
    public static func workspaceToLearn(_ url: URL, settings: AppSettings) -> String? {
        guard case .subdomain(let name)? = SlackLink(url)?.workspace,
            settings.slackTeamID(forWorkspace: name) == nil
        else { return nil }
        return name
    }

    /// A workspace subdomain and team ID that a link shows together (acme.slack.com/lists/T…/…),
    /// so TrafficControl can remember the workspace without asking Slack.
    public static func workspaceShown(in url: URL) -> (subdomain: String, teamID: String)? {
        guard let host = url.host()?.lowercased(), host.hasSuffix(".slack.com"), host != "app.slack.com",
            case .teamID(let team)? = SlackLink(url)?.workspace
        else { return nil }
        return (String(host.dropLast(".slack.com".count)), team)
    }

    /// The team ID in a response from slack.com/api/auth.findTeam.
    public static func teamID(fromFindTeamResponse data: Data) -> String? {
        struct Response: Decodable {
            let ok: Bool
            let team_id: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.ok,
            let id = response.team_id
        else { return nil }
        return AppSettings.slackTeamID(from: id)
    }
}
