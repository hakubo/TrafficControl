import AppKit
import Combine
import SwiftUI

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
        item.menu = menu
        statusItem = item
        updateStatusIcon(isDefault: defaultStatus.isDefault)
    }

    /// The menu bar icon gets an orange dot while links aren't reaching TrafficControl.
    private func updateStatusIcon(isDefault: Bool) {
        guard let button = statusItem?.button,
              let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "TrafficControl")
        else { return }
        button.toolTip = isDefault ? "TrafficControl" : "TrafficControl isn't your default browser"
        guard !isDefault else {
            button.image = symbol
            return
        }
        let base = symbol.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? symbol
        let size = NSSize(width: base.size.width + 3, height: base.size.height + 2)
        // Drawn at display time, so the symbol takes the menu bar's current text color.
        let image = NSImage(size: size, flipped: false) { rect in
            let tinted = base.withSymbolConfiguration(.init(paletteColors: [.labelColor])) ?? base
            tinted.draw(in: NSRect(x: 0, y: 1, width: base.size.width, height: base.size.height))
            let dot = NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 7, height: 7)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "TrafficControl isn't your default browser"
        button.image = image
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
        clipboard.isEnabled = clipboardURL != nil
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        if updater.isAvailable {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Buy Me a Coffee…", action: #selector(buyMeACoffee), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit TrafficControl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

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
        if settingsWindow == nil {
            browsers.refresh()
            let root = SettingsView()
                .environmentObject(settings)
                .environmentObject(browsers)
                .environmentObject(history)
                .environmentObject(updater)
                .environmentObject(defaultStatus)
            // A full-size content view plus an (empty) unified toolbar lets the sidebar run under the
            // title bar, like System Settings; SettingsView sets the title to the selected pane.
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: root)
            let toolbar = NSToolbar()
            // The toolbar has no items, so its right-click "Icon and Text / Icon Only / Text Only" menu
            // would do nothing. (macOS 14 has no way to turn it off.)
            if #available(macOS 15.0, *) { toolbar.allowsDisplayModeCustomization = false }
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.title = "TrafficControl"
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 907, height: 821))
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.delegate = self
            window.center()
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
