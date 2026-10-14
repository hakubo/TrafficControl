import AppKit
import ServiceManagement
import Sparkle
import TrafficControlCore

/// Settings that persist to disk on every change.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            do { try store.save(settings) } catch { NSLog("TrafficControl: failed to save settings: \(error)") }
        }
    }

    private let store: SettingsStore

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.settings = store.load()
    }
}

/// Domains of opened links and where they went. Saved separately from settings since it changes on every click.
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var history: LinkHistory
    private let store: HistoryStore

    init(store: HistoryStore = HistoryStore()) {
        self.store = store
        self.history = store.load()
    }

    func record(_ url: URL, destination: LinkDestination) {
        history.record(url, destination: destination)
        save()
    }

    func remove(_ domain: String) {
        history.remove(domain)
        save()
    }

    func clear() {
        history.clear()
        save()
    }

    private func save() {
        do { try store.save(history) } catch { NSLog("TrafficControl: failed to save history: \(error)") }
    }
}

/// Sparkle's updater, exposed to SwiftUI. Only started when running as a bundled app, since
/// `swift run` has no Info.plist and so no feed URL or public key.
@MainActor
final class UpdaterModel: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    init() {
        let bundled = Bundle.main.bundleURL.pathExtension == "app"
        controller = bundled
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            controller?.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

enum Links {
    static let website = URL(string: "https://hakubo.github.io/TrafficControl/")!
    static let repository = URL(string: "https://github.com/hakubo/TrafficControl")!
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/jakubolek")!
}

enum DefaultBrowser {
    static var isDefault: Bool {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let id = Bundle(url: url)?.bundleIdentifier
        else { return false }
        return id == Bundle.main.bundleIdentifier
    }

    /// macOS asks the user to confirm each scheme change.
    static func makeDefault(completion: @escaping () -> Void = {}) {
        let app = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https") { error in
                if let error { NSLog("TrafficControl: could not become default browser: \(error)") }
                DispatchQueue.main.async(execute: completion)
            }
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("TrafficControl: login item change failed: \(error)")
        }
    }
}
