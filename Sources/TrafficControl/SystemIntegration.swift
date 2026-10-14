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
    private let writer = DispatchQueue(label: "TrafficControl.history-writer")
    private var pendingSave: DispatchWorkItem?

    init(store: HistoryStore = HistoryStore()) {
        self.store = store
        self.history = store.load()
    }

    func record(_ url: URL, destination: LinkDestination, picked: Bool = false) {
        history.record(url, destination: destination, picked: picked)
        scheduleSave()
    }

    func remove(_ domain: String) {
        history.remove(domain)
        saveNow()
    }

    func clear() {
        history.clear()
        saveNow()
    }

    /// Writes any pending change and waits for it. Call when the app quits.
    func flush() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        let snapshot = history, store = store
        writer.sync { Self.write(snapshot, to: store) }
    }

    /// Clicks arrive in bursts; coalesce them into one write a second after the last.
    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    /// Encodes and writes off the main thread. The queue is serial so an older snapshot can't land after a newer one.
    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let snapshot = history, store = store
        writer.async { Self.write(snapshot, to: store) }
    }

    private nonisolated static func write(_ history: LinkHistory, to store: HistoryStore) {
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
        controller =
            bundled
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
    static let automationSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
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

/// Whether TrafficControl is the default browser, kept current: another browser can take over at
/// any time (many ask on launch), and then links silently stop arriving here.
@MainActor
final class DefaultBrowserStatus: ObservableObject {
    @Published private(set) var isDefault = DefaultBrowser.isDefault
    private var timer: Timer?
    private var activation: NSObjectProtocol?

    init() {
        // Slow background poll (the menu and activation hooks refresh promptly); the tolerance
        // lets the OS coalesce wakeups.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 10
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let now = DefaultBrowser.isDefault
        if now != isDefault { isDefault = now }
    }

    func makeDefault() {
        DefaultBrowser.makeDefault { [weak self] in self?.refresh() }
    }
}

enum LoginItem {
    /// On when registered, including while macOS is still waiting for the user's approval.
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("TrafficControl: login item change failed: \(error)")
        }
    }
}
