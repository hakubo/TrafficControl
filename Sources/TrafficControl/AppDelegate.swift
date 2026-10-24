import AppKit
import Combine
import SwiftUI
import TrafficControlCore

@main
enum TrafficControlMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings = SettingsModel()
    let history = HistoryModel()
    let updater = UpdaterModel()
    let defaultStatus = DefaultBrowserStatus()
    lazy var browsers = BrowserManager()
    lazy var picker = PickerController(settings: settings, browsers: browsers, history: history)
    lazy var router = LinkRouter(settings: settings, browsers: browsers, picker: picker, history: history)

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let menuBar = MenuBarModel()
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var receivedLinkAtLaunch = false
    private var overrideTimer: Timer?

    func applicationWillTerminate(_ notification: Notification) {
        history.flush()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        settings.$settings
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] show in self?.updateStatusItem(visible: show) }
            .store(in: &cancellables)
        defaultStatus.$isDefault
            .sink { [weak self] isDefault in self?.updateStatusIcon(isDefault: isDefault) }
            .store(in: &cancellables)

        // Launched by hand rather than by a link: help the user finish setting up.
        if !receivedLinkAtLaunch && !defaultStatus.isDefault {
            showSettings()
        }
    }

    /// Links and HTML files both arrive here. The current Apple event tells us which app sent them.
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedLinkAtLaunch = true
        let event = NSAppleEventManager.shared().currentAppleEvent
        let pid = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        router.route(urls, senderPID: pid)
    }

    /// Opening the app again (e.g. from Finder) with the menu bar icon hidden shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: - Menu bar

    private func updateStatusItem(visible: Bool) {
        if !visible {
            popover?.close()
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        updateStatusIcon(isDefault: defaultStatus.isDefault)
    }

    /// The menu bar icon gets an orange dot while links aren't reaching TrafficControl,
    /// and the accent color while "Send All Links To" is on.
    private func updateStatusIcon(isDefault: Bool) {
        guard let button = statusItem?.button else { return }
        let override = activeOverride
        button.toolTip = [
            isDefault ? "TrafficControl" : "TrafficControl isn't your default browser",
            override.map { "Sending all links to \(browsers.title(for: $0.target)) until \(Self.time($0.until))" },
        ].compactMap { $0 }.joined(separator: "\n")
        // Tints only the template tower; the orange-dot image is drawn in its own colors.
        button.contentTintColor = override == nil ? nil : .controlAccentColor
        button.image = isDefault ? StatusIcon.template() : StatusIcon.withWarningDot()
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        defaultStatus.refresh()
        menuBar.override = activeOverride
        detectClipboardURL()
        let popover = popover ?? makePopover()
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // An accessory app's popover only takes keys (⌘, / ⌘Q) once its window is key.
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        menuBar.startOverride = { [weak self] target in
            self?.setOverride(TemporaryOverride(target: target, until: Date().addingTimeInterval(60 * 60)))
        }
        menuBar.stopOverride = { [weak self] in self?.setOverride(nil) }
        menuBar.openClipboard = { [weak self] in self?.closePopover { $0.openClipboard() } }
        menuBar.makeDefault = { [weak self] in self?.defaultStatus.makeDefault() }
        menuBar.showSettings = { [weak self] in self?.closePopover { $0.showSettings() } }
        menuBar.checkForUpdates = { [weak self] in self?.closePopover { $0.updater.checkForUpdates() } }
        menuBar.buyMeACoffee = { [weak self] in self?.closePopover { _ in NSWorkspace.shared.open(Links.buyMeACoffee) } }
        let root = MenuBarPopover(model: menuBar)
            .environmentObject(settings)
            .environmentObject(browsers)
            .environmentObject(history)
            .environmentObject(updater)
            .environmentObject(defaultStatus)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        return popover
    }

    private func closePopover(then action: (AppDelegate) -> Void) {
        popover?.performClose(nil)
        action(self)
    }

    // MARK: - Send All Links To

    private var activeOverride: TemporaryOverride? {
        router.override.flatMap { $0.isActive(at: Date()) ? $0 : nil }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The router checks the expiry itself; the timer only clears the menu bar icon and tooltip on time.
    private func setOverride(_ override: TemporaryOverride?) {
        router.override = override
        menuBar.override = override
        overrideTimer?.invalidate()
        overrideTimer = nil
        if let override {
            let timer = Timer(fire: override.until, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.setOverride(nil) }
            }
            RunLoop.main.add(timer, forMode: .common)
            overrideTimer = timer
        }
        updateStatusIcon(isDefault: defaultStatus.isDefault)
    }

    /// Checks whether the pasteboard probably holds a web URL, without reading its contents
    /// (reading on every popover open can trigger macOS's paste-privacy alert).
    private func detectClipboardURL() {
        guard #available(macOS 15.4, *) else {
            menuBar.clipboardHasURL = true
            return
        }
        menuBar.clipboardHasURL = false
        let model = menuBar
        // The Swift overlay for this API isn't in this SDK, so call the refined ObjC entry point.
        NSPasteboard.general.__detectPatterns(forPatterns: [.__probableWebURL]) { patterns, _ in
            let found = patterns?.contains(.__probableWebURL) ?? false
            DispatchQueue.main.async { MainActor.assumeIsolated { model.clipboardHasURL = found } }
        }
    }

    /// Reads the pasteboard; call only when the user chooses the clipboard item.
    private var clipboardURL: URL? {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let url = URL(string: text), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else { return nil }
        return url
    }

    private func openClipboard() {
        guard let url = clipboardURL else { return }
        picker.enqueue(PickerRequest(url: url, sourceApp: nil))
    }

    @objc func showSettings() {
        browsers.refresh()
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(settings)
                .environmentObject(browsers)
                .environmentObject(history)
                .environmentObject(updater)
                .environmentObject(defaultStatus)
            // A full-size content view plus an (empty) unified toolbar lets the sidebar run under the
            // title bar, like System Settings; SettingsView's .navigationTitle names the selected pane.
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "TrafficControl"  // Replaced by the pane's .navigationTitle once SwiftUI loads.
            let host = NSHostingController(rootView: root)
            // Don't let SwiftUI resize the window to its ideal size; keep the default/autosaved frame.
            // SettingsView's minimum frame still sets the window's minimum size.
            host.sizingOptions = [.minSize]
            window.contentViewController = host
            let toolbar = NSToolbar()
            // The toolbar has no items, so its right-click "Icon and Text / Icon Only / Text Only" menu
            // would do nothing. (macOS 14 has no way to turn it off.)
            if #available(macOS 15.0, *) { toolbar.allowsDisplayModeCustomization = false }
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 907, height: 680))
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.delegate = self
            // Centre at the default size; the autosave name then restores a saved frame if there is one.
            window.center()
            window.setFrameAutosaveName("Settings")
            settingsWindow = window
        }
        guard let window = settingsWindow else { return }

        // While Settings is open, TrafficControl acts like a regular app (Dock icon, ⌘-Tab) so the
        // window can't get lost behind others; windowWillClose turns it back into a menu bar app.
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is cooperative since macOS 14 and can be declined; this raises the window regardless.
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Never shown while TrafficControl is a menu bar app, but its key equivalents still route
    /// ⌘C/⌘V/⌘A/⌘Z to text fields in Settings, and ⌘W/⌘Q/⌘, work.
    private func installMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide TrafficControl", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit TrafficControl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "TrafficControl", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }
}
