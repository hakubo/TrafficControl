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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let settings = SettingsModel()
    let history = HistoryModel()
    let updater = UpdaterModel()
    let defaultStatus = DefaultBrowserStatus()
    lazy var browsers = BrowserManager()
    lazy var picker = PickerController(settings: settings, browsers: browsers, history: history)
    lazy var router = LinkRouter(settings: settings, browsers: browsers, picker: picker, history: history)

    private var statusItem: NSStatusItem?
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
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        // Items set isEnabled themselves (the clipboard item); auto-enabling would override it.
        menu.autoenablesItems = false
        item.menu = menu
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        defaultStatus.refresh()
        if !defaultStatus.isDefault {
            let warning = menu.addItem(withTitle: "Links aren't coming to TrafficControl", action: nil, keyEquivalent: "")
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
            warning.isEnabled = false
            if #available(macOS 14.4, *) {
                warning.subtitle = "Another app is your default browser."
            }
            menu.addItem(withTitle: "Make TrafficControl the Default Browser", action: #selector(makeDefault), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        let clipboard = menu.addItem(withTitle: "Open Link from Clipboard", action: #selector(openClipboard), keyEquivalent: "")
        clipboard.target = self
        enableWhenClipboardHoldsURL(clipboard)
        addOverrideItems(to: menu)
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        if updater.isAvailable {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Buy Me a Coffee…", action: #selector(buyMeACoffee), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit TrafficControl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: - Send All Links To

    private var activeOverride: TemporaryOverride? {
        router.override.flatMap { $0.isActive(at: Date()) ? $0 : nil }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// A submenu of browsers (and profiles) that takes over routing for an hour, e.g. during a screen share.
    private func addOverrideItems(to menu: NSMenu) {
        let choices = browsers.orderedChoices(settings.settings, includeHidden: false)
        guard !choices.isEmpty else { return }
        let override = activeOverride
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(.sectionHeader(title: "For the Next Hour"))
        for choice in choices {
            let item = submenu.addItem(withTitle: choice.menuTitle, action: #selector(startOverride(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.target
            item.state = override?.target == choice.target ? .on : .off
            let icon = (choice.avatar ?? choice.browser.icon).copy() as? NSImage
            icon?.size = NSSize(width: 16, height: 16)
            item.image = icon
        }

        let parent = menu.addItem(withTitle: "Send All Links To", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        guard let override else { return }
        let name = browsers.title(for: override.target)
        parent.title = "Sending All Links to \(name)"
        if #available(macOS 14.4, *) {
            parent.subtitle = "Until \(Self.time(override.until))"
        } else {
            parent.title += " Until \(Self.time(override.until))"
        }
        menu.addItem(withTitle: "Stop Sending All Links to \(name)", action: #selector(stopOverride), keyEquivalent: "").target = self
    }

    @objc private func startOverride(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? BrowserTarget else { return }
        setOverride(TemporaryOverride(target: target, until: Date().addingTimeInterval(60 * 60)))
    }

    @objc private func stopOverride() {
        setOverride(nil)
    }

    /// The router checks the expiry itself; the timer only clears the menu bar icon and tooltip on time.
    private func setOverride(_ override: TemporaryOverride?) {
        router.override = override
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

    /// Enables the item if the pasteboard probably holds a web URL, without reading its contents
    /// (reading on every menu open can trigger macOS's paste-privacy alert).
    private func enableWhenClipboardHoldsURL(_ item: NSMenuItem) {
        guard #available(macOS 15.4, *) else { return }
        item.isEnabled = false
        nonisolated(unsafe) let item = item
        // The Swift overlay for this API isn't in this SDK, so call the refined ObjC entry point.
        NSPasteboard.general.__detectPatterns(forPatterns: [.__probableWebURL]) { patterns, _ in
            let found = patterns?.contains(.__probableWebURL) ?? false
            DispatchQueue.main.async { item.isEnabled = found }
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

    @objc private func openClipboard() {
        guard let url = clipboardURL else { return }
        picker.enqueue(PickerRequest(url: url, sourceApp: nil))
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func buyMeACoffee() {
        NSWorkspace.shared.open(Links.buyMeACoffee)
    }

    @objc private func makeDefault() {
        defaultStatus.makeDefault()
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
