import Foundation

/// A browser, optionally narrowed to one of its profiles. `profileID` is the profile's
/// directory name (e.g. "Default", "Profile 2"), which is what Chromium's command line takes.
public struct BrowserTarget: Codable, Hashable, Sendable {
    public var browserID: String
    public var profileID: String?

    public init(browserID: String, profileID: String? = nil) {
        self.browserID = browserID
        self.profileID = profileID
    }
}

public struct BrowserProfile: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// The signed-in account, if any.
    public let userName: String?
    public let avatarPath: String?

    public init(id: String, name: String, userName: String? = nil, avatarPath: String? = nil) {
        self.id = id
        self.name = name
        self.userName = userName
        self.avatarPath = avatarPath
    }
}

/// Reads profiles of Chromium-based browsers from their `Local State` file.
public enum ChromiumProfiles {
    /// Bundle identifier → user data directory under ~/Library/Application Support.
    public static let userDataDirectories: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.brave.Browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    public static func supports(_ bundleID: String) -> Bool {
        userDataDirectories[bundleID] != nil
    }

    public static func load(
        for bundleID: String, applicationSupport: URL = .applicationSupportDirectory
    ) -> [BrowserProfile] {
        guard let relative = userDataDirectories[bundleID] else { return [] }
        let dir = applicationSupport.appending(path: relative, directoryHint: .isDirectory)
        guard let data = try? Data(contentsOf: dir.appending(path: "Local State")) else { return [] }
        return parseLocalState(data, userDataDirectory: dir)
    }

    /// Profiles in the order the browser shows them; `Default` first when no order is recorded.
    public static func parseLocalState(_ data: Data, userDataDirectory: URL? = nil) -> [BrowserProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]]
        else { return [] }

        let order = (profile["profiles_order"] as? [String]) ?? []
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        return cache.compactMap { dir, info -> BrowserProfile? in
            if info["is_ephemeral"] as? Bool == true { return nil }
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? dir
            let userName = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let avatar = (info["gaia_picture_file_name"] as? String).flatMap { file -> String? in
                guard !file.isEmpty, let base = userDataDirectory else { return nil }
                return base.appending(path: dir).appending(path: file).path(percentEncoded: false)
            }
            return BrowserProfile(id: dir, name: name, userName: userName, avatarPath: avatar)
        }
        .sorted { a, b in
            let ra = rank[a.id] ?? (a.id == "Default" ? -1 : Int.max)
            let rb = rank[b.id] ?? (b.id == "Default" ? -1 : Int.max)
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Arguments that open `urls` in a given profile. Chromium forwards them to its running instance.
    public static func launchArguments(profileID: String, urls: [URL]) -> [String] {
        ["--profile-directory=\(profileID)"] + urls.map(\.absoluteString)
    }
}
