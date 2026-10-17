import AppKit
import TrafficControlCore

struct Browser: Identifiable, Hashable {
    /// The bundle identifier.
    let id: String
    let name: String
    let appURL: URL

    var icon: NSImage { ImageCache.appIcon(atPath: appURL.path) }
}

/// App icons and profile avatars, so rendering and `orderedChoices` don't hit the disk every time.
enum ImageCache {
    private nonisolated(unsafe) static let icons = NSCache<NSString, NSImage>()
    private nonisolated(unsafe) static let avatars = NSCache<NSString, NSImage>()

    static func appIcon(atPath path: String) -> NSImage {
        if let hit = icons.object(forKey: path as NSString) { return hit }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(icon, forKey: path as NSString)
        return icon
    }

    /// Keyed by path and modification date, so a changed picture is picked up.
    static func avatar(atPath path: String?) -> NSImage? {
        guard let path,
            let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return nil }
        let key = "\(path)@\(modified.timeIntervalSince1970)" as NSString
        if let hit = avatars.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        avatars.setObject(image, forKey: key)
        return image
    }
}

/// One choice in the picker or in a menu: a browser, one profile of a multi-profile browser,
/// or a desktop app that can open the link itself (then `browser` is that app).
struct BrowserChoice: Identifiable {
    let browser: Browser
    let profile: BrowserProfile?
    var avatar: NSImage? = nil
    var deepLink: URL? = nil

    var id: String { browser.id + "/" + (profile?.id ?? "") }
    var target: BrowserTarget { BrowserTarget(browserID: browser.id, profileID: profile?.id) }
    var destination: LinkDestination { deepLink != nil ? .app(bundleID: browser.id) : .browser(target) }
    var title: String { profile?.name ?? browser.name }
    var menuTitle: String { profile.map { "\(browser.name) – \($0.name)" } ?? browser.name }
}

/// Finds installed browsers, tracks which ones are running and opens links in them.
@MainActor
final class BrowserManager: ObservableObject {
    @Published private(set) var installed: [Browser] = []
    /// Profiles of Chromium-based browsers, keyed by bundle identifier.
    @Published private(set) var profiles: [String: [BrowserProfile]] = [:]
    private(set) var lastActiveBrowserID: String?
    private var activationObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?

    init() {
        refresh()
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, browser(withID: front) != nil {
            lastActiveBrowserID = front
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                guard let self, self.browser(withID: id) != nil else { return }
                self.lastActiveBrowserID = id
            }
        }

        // A browser installed after launch usually gets opened once; that is the cue to look again.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                guard let self, self.browser(withID: id) == nil, id != Bundle.main.bundleIdentifier else { return }
                self.refresh()
            }
        }
    }

    /// Every app registered for https, except TrafficControl itself.
    func refresh() {
        let probe = URL(string: "https://example.com")!
        var seen: Set<String> = []
        if let own = Bundle.main.bundleIdentifier { seen.insert(own) }
        let found = NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url -> Browser? in
            guard let bundle = Bundle(url: url),
                let id = bundle.bundleIdentifier,
                seen.insert(id).inserted
            else { return nil }
            let name =
                bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            return Browser(id: id, name: name, appURL: url)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if found != installed { installed = found }
        refreshProfiles()
    }

    /// Cheap enough to run on every click, so profiles added in Chrome show up straight away.
    func refreshProfiles() {
        var found: [String: [BrowserProfile]] = [:]
        for browser in installed where ChromiumProfiles.supports(browser.id) {
            let list = ChromiumProfiles.load(for: browser.id)
            if !list.isEmpty { found[browser.id] = list }
        }
        if found != profiles { profiles = found }
    }

    /// Profiles worth choosing between; a browser with a single profile is just the browser.
    func selectableProfiles(for browserID: String) -> [BrowserProfile] {
        let list = profiles[browserID] ?? []
        return list.count > 1 ? list : []
    }

    /// What the picker shows: the desktop app for this link (if any), then the visible entries of `orderedChoices`.
    func pickerChoices(_ settings: AppSettings, for url: URL? = nil) -> [BrowserChoice] {
        var app: [BrowserChoice] = []
        if let url, let (link, deepLink) = AppLink.first(for: url), settings.appLinkMode(for: link.id) != .never,
            let appURL = appURL(for: link.bundleID)
        {
            app = [BrowserChoice(browser: Browser(id: link.bundleID, name: link.name, appURL: appURL), profile: nil, deepLink: deepLink)]
        }
        return app + orderedChoices(settings, includeHidden: false)
    }

    /// Browsers in the picker's order, with multi-profile browsers expanded into one entry per profile.
    func orderedChoices(_ settings: AppSettings, includeHidden: Bool) -> [BrowserChoice] {
        let all = ordered(settings, includeHidden: true).flatMap { browser -> [BrowserChoice] in
            let list = selectableProfiles(for: browser.id)
            guard !list.isEmpty else { return [BrowserChoice(browser: browser, profile: nil)] }
            return list.map { BrowserChoice(browser: browser, profile: $0, avatar: ImageCache.avatar(atPath: $0.avatarPath)) }
        }
        return settings.sortedByChoiceOrder(all, target: \.target)
            .filter { includeHidden || !settings.isHidden($0.target) }
    }

    /// Every browser plus each of its profiles, for rule and primary-browser menus.
    func menuChoices(_ settings: AppSettings) -> [BrowserChoice] {
        ordered(settings, includeHidden: true).flatMap { browser in
            [BrowserChoice(browser: browser, profile: nil)]
                + selectableProfiles(for: browser.id).map { BrowserChoice(browser: browser, profile: $0) }
        }
    }

    func title(for destination: LinkDestination) -> String {
        switch destination {
        case .browser(let target): title(for: target)
        case .app(let id): AppLink.all.first { $0.bundleID == id }?.name ?? id
        }
    }

    func title(for target: BrowserTarget) -> String {
        guard let browser = browser(withID: target.browserID) else { return target.browserID }
        guard let id = target.profileID else { return browser.name }
        let name = profiles[browser.id]?.first { $0.id == id }?.name ?? id
        return "\(browser.name) – \(name)"
    }

    // MARK: Desktop apps

    func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var installedAppLinkIDs: Set<String> {
        Set(AppLink.all.map(\.bundleID).filter { appURL(for: $0) != nil })
    }

    var runningAppLinkIDs: Set<String> {
        let ids = Set(AppLink.all.map(\.bundleID))
        return Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter(ids.contains))
    }

    func openInApp(_ deepLink: URL, bundleID: String) {
        guard let app = appURL(for: bundleID) else { return }
        let start = ContinuousClock.now
        NSWorkspace.shared.open([deepLink], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Timing.report("hand link to \(bundleID)", since: start)
            if let error { NSLog("TrafficControl: failed to open \(deepLink) in \(bundleID): \(error)") }
        }
    }

    func browser(withID id: String) -> Browser? {
        installed.first { $0.id == id }
    }

    var runningBrowserIDs: [String] {
        let ids = Set(installed.map(\.id))
        return NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter(ids.contains)
    }

    /// Installed browsers, alphabetically; `orderedChoices` applies the user's order.
    func ordered(_ settings: AppSettings, includeHidden: Bool) -> [Browser] {
        let hidden = Set(settings.hiddenBrowserIDs)
        return installed.filter { includeHidden || !hidden.contains($0.id) }
    }

    /// Switches to a tab of `browser` already showing the link when `reuseTab` is set, otherwise opens it.
    func openOrSwitch(_ url: URL, in browser: Browser, profileID: String?, inBackground: Bool, reuseTab: Bool) {
        if reuseTab, let tab = Timing.measure("find open tab (target browser)", { OpenTabFinder.find(url, in: [browser.id]) }),
            Timing.measure("focus tab", { OpenTabFinder.focus(tab, activate: !inBackground) })
        {
            return
        }
        open([url], in: browser, profileID: profileID, inBackground: inBackground)
    }

    func open(_ urls: [URL], in browser: Browser, profileID: String? = nil, inBackground: Bool) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !inBackground
        let start = ContinuousClock.now
        if let profileID, !inBackground, runningBrowserIDs.contains(browser.id),
            let executable = Bundle(url: browser.appURL)?.executableURL
        {
            // The browser is already running: start its executable directly. It hands the arguments to the
            // running browser and exits, without the cost of LaunchServices registering a new app instance.
            let process = Process()
            process.executableURL = executable
            process.arguments = ChromiumProfiles.launchArguments(profileID: profileID, urls: urls)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in Timing.report("hand off to \(browser.name) for profile \(profileID)", since: start) }
            do {
                try process.run()
                return
            } catch {
                NSLog("TrafficControl: failed to start \(executable.path): \(error)")
            }
        }
        if let profileID {
            // Like `open -n --args`: a fresh process receives the arguments and hands them to the
            // running browser, which opens the links in that profile's window.
            config.createsNewApplicationInstance = true
            config.arguments = ChromiumProfiles.launchArguments(profileID: profileID, urls: urls)
            NSWorkspace.shared.openApplication(at: browser.appURL, configuration: config) { _, error in
                Timing.report("launch \(browser.name) for profile \(profileID)", since: start)
                if let error { NSLog("TrafficControl: failed to open in \(browser.name) (\(profileID)): \(error)") }
            }
            return
        }
        NSWorkspace.shared.open(urls, withApplicationAt: browser.appURL, configuration: config) { _, error in
            Timing.report("hand link to \(browser.name)", since: start)
            if let error { NSLog("TrafficControl: failed to open in \(browser.name): \(error)") }
        }
    }
}
