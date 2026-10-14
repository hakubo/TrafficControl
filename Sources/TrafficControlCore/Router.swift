import Foundation

/// The state of the machine that routing depends on, gathered by the app at click time.
public struct RoutingEnvironment: Sendable {
    public var installedBrowserIDs: Set<String>
    /// Known profiles per browser bundle identifier.
    public var installedProfiles: [String: Set<String>]
    public var runningBrowserIDs: [String]
    /// Bundle identifiers of the desktop apps in `AppLink.all` that are installed / running.
    public var installedAppIDs: Set<String>
    public var runningAppIDs: Set<String>
    public var lastActiveBrowserID: String?
    /// The user held the "always ask" modifier while clicking.
    public var forcePicker: Bool

    public init(
        installedBrowserIDs: Set<String>,
        installedProfiles: [String: Set<String>] = [:],
        runningBrowserIDs: [String] = [],
        installedAppIDs: Set<String> = [],
        runningAppIDs: Set<String> = [],
        lastActiveBrowserID: String? = nil,
        forcePicker: Bool = false
    ) {
        self.installedBrowserIDs = installedBrowserIDs
        self.installedProfiles = installedProfiles
        self.runningBrowserIDs = runningBrowserIDs
        self.installedAppIDs = installedAppIDs
        self.runningAppIDs = runningAppIDs
        self.lastActiveBrowserID = lastActiveBrowserID
        self.forcePicker = forcePicker
    }

    /// A profile that no longer exists must not be passed on: Chromium would create it as a new, empty profile.
    public func canOpen(_ target: BrowserTarget) -> Bool {
        guard installedBrowserIDs.contains(target.browserID) else { return false }
        guard let profile = target.profileID else { return true }
        return installedProfiles[target.browserID]?.contains(profile) ?? false
    }
}

public enum RoutingDecision: Equatable, Sendable {
    case open(BrowserTarget, ruleID: UUID?)
    /// Open `url` (a deep link) with the desktop app `bundleID`.
    case openInApp(bundleID: String, url: URL)
    case ask
}

public enum Router {
    /// Rules are evaluated top to bottom; the first matching rule whose browser (and profile) exists wins.
    /// A rule pointing at an uninstalled browser or a deleted profile is skipped rather than failing the click.
    public static func decide(
        _ context: LinkContext,
        settings: AppSettings,
        environment env: RoutingEnvironment
    ) -> RoutingDecision {
        if env.forcePicker { return .ask }

        // Desktop apps come before rules: each one is an explicit opt-in with its own setting,
        // and a broad rule (say, everything from Slack goes to Chrome) shouldn't swallow it.
        if let (app, deepLink) = AppLink.first(for: context.url) {
            let available: Bool
            switch settings.appLinkMode(for: app.id) {
            case .whenRunning: available = env.runningAppIDs.contains(app.bundleID)
            case .whenInstalled: available = env.installedAppIDs.contains(app.bundleID)
            case .never: available = false
            }
            if available { return .openInApp(bundleID: app.bundleID, url: deepLink) }
        }

        for rule in settings.rules where rule.matches(context) {
            switch rule.action {
            case .ask:
                return .ask
            case .open(let id, let profile):
                let target = BrowserTarget(browserID: id, profileID: profile)
                if env.canOpen(target) { return .open(target, ruleID: rule.id) }
            }
        }

        let hidden = Set(settings.hiddenBrowserIDs)
        let running = env.runningBrowserIDs.filter {
            env.installedBrowserIDs.contains($0) && !hidden.contains($0)
        }

        switch settings.defaultBehavior {
        case .alwaysAsk:
            return .ask
        case .primaryBrowser:
            if let target = settings.primaryBrowser, env.canOpen(target) {
                return .open(target, ruleID: nil)
            }
        case .runningBrowser:
            if running.count == 1 { return .open(BrowserTarget(browserID: running[0]), ruleID: nil) }
        case .lastActiveBrowser:
            if let id = env.lastActiveBrowserID, running.contains(id) {
                return .open(BrowserTarget(browserID: id), ruleID: nil)
            }
            if running.count == 1 { return .open(BrowserTarget(browserID: running[0]), ruleID: nil) }
        }
        return .ask
    }

    public static func firstMatchingRule(_ context: LinkContext, in rules: [Rule]) -> Rule? {
        rules.first { $0.matches(context) }
    }
}
