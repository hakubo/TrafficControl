import Foundation

/// What to do with a link that no rule claims.
public enum DefaultBehavior: String, Codable, CaseIterable, Sendable, Hashable {
    case alwaysAsk
    case primaryBrowser
    case runningBrowser
    case lastActiveBrowser

    public var label: String {
        switch self {
        case .alwaysAsk: "Always show the picker"
        case .primaryBrowser: "Open in the primary browser"
        case .runningBrowser: "Use the running browser if only one is open"
        case .lastActiveBrowser: "Use the most recently used running browser"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var defaultBehavior: DefaultBehavior = .alwaysAsk
    public var primaryBrowser: BrowserTarget?
    public var browserOrder: [String] = []
    public var hiddenBrowserIDs: [String] = []
    public var hiddenProfiles: [BrowserTarget] = []
    public var rules: [Rule] = []
    /// Per `AppLink.id`; apps not listed use `defaultAppLinkMode`.
    public var appLinkModes: [String: AppLinkMode] = [:]
    public var showURLInPicker = true
    public var showMenuBarIcon = true
    public var forcePickerWithOption = true
    public var rememberDomains = true
    public var tabReuse = TabReuseMode.anyBrowser

    public init() {}

    public static let defaultAppLinkMode = AppLinkMode.whenRunning

    public func appLinkMode(for id: String) -> AppLinkMode {
        appLinkModes[id] ?? Self.defaultAppLinkMode
    }

    private enum CodingKeys: String, CodingKey {
        case defaultBehavior, primaryBrowser, browserOrder, hiddenBrowserIDs, hiddenProfiles, rules, appLinkModes
        case showURLInPicker, showMenuBarIcon, forcePickerWithOption, rememberDomains, tabReuse
    }

    // Every key is optional so settings files written by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        defaultBehavior = try c.decodeIfPresent(DefaultBehavior.self, forKey: .defaultBehavior) ?? d.defaultBehavior
        primaryBrowser = try c.decodeIfPresent(BrowserTarget.self, forKey: .primaryBrowser)
        browserOrder = try c.decodeIfPresent([String].self, forKey: .browserOrder) ?? d.browserOrder
        hiddenBrowserIDs = try c.decodeIfPresent([String].self, forKey: .hiddenBrowserIDs) ?? d.hiddenBrowserIDs
        hiddenProfiles = try c.decodeIfPresent([BrowserTarget].self, forKey: .hiddenProfiles) ?? d.hiddenProfiles
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? d.rules
        appLinkModes = try c.decodeIfPresent([String: AppLinkMode].self, forKey: .appLinkModes) ?? d.appLinkModes
        showURLInPicker = try c.decodeIfPresent(Bool.self, forKey: .showURLInPicker) ?? d.showURLInPicker
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        forcePickerWithOption = try c.decodeIfPresent(Bool.self, forKey: .forcePickerWithOption) ?? d.forcePickerWithOption
        rememberDomains = try c.decodeIfPresent(Bool.self, forKey: .rememberDomains) ?? d.rememberDomains
        tabReuse = try c.decodeIfPresent(TabReuseMode.self, forKey: .tabReuse) ?? d.tabReuse
    }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "TrafficControl", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
