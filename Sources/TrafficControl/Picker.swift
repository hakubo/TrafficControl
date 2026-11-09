import AppKit
import Combine
import SwiftUI
import TrafficControlCore

struct PickerRequest: Identifiable {
    let id = UUID()
    let url: URL
    let sourceApp: NSRunningApplication?
}

@MainActor
final class PickerModel: ObservableObject {
    let url: URL
    let sourceName: String?
    let sourceIcon: NSImage?
    let choices: [BrowserChoice]
    let showURL: Bool
    /// The one browser Return opens, a ⌘-pick remembers and the ⌘ banner names. Moving the pointer
    /// onto a tile selects it, so the pointer and the keyboard can never disagree about it.
    @Published var selection: Int
    /// ⌘ is held: the pick also becomes the rule for this domain.
    @Published var remembering = false
    /// Full keyboard hint line vs. a "?" tooltip once the user has seen it a few times.
    var showFullHint = true
    var onChoose: (Int, Bool) -> Void = { _, _ in }

    /// "github.com", the part of the link a remembered pick applies to.
    var domain: String? { LinkAddress.of(url, depth: 0) }

    /// The entry ⌘-Return or a ⌘-click would remember.
    var rememberTarget: BrowserChoice? {
        choices.indices.contains(selection) ? choices[selection] : nil
    }

    private var pointerGate = PointerGate(origin: NSEvent.mouseLocation)

    /// The pointer moved onto a tile. The picker opens centred on the pointer, so the tile under it
    /// is "entered" before the user moves at all; that must not replace the preselected browser.
    func pointerEntered(_ index: Int) {
        if pointerGate.moved(to: NSEvent.mouseLocation) { selection = index }
    }

    /// A click on a tile. Returns false when the click only selected it: with ⌘ held and a pointer
    /// that hasn't moved since the picker opened, the banner still names the preselected browser, so
    /// saving the clicked one would remember a different browser from the one shown.
    func click(_ index: Int) -> Bool {
        let confirmed = index == selection || !remembering
        selection = index
        return confirmed
    }

    init(
        url: URL, sourceName: String?, sourceIcon: NSImage?, choices: [BrowserChoice], showURL: Bool, selection: Int
    ) {
        self.url = url
        self.sourceName = sourceName
        self.sourceIcon = sourceIcon
        self.choices = choices
        self.showURL = showURL
        self.selection = selection
    }
}

/// A borderless panel that can take keyboard focus without activating TrafficControl,
/// so the app you clicked the link in stays frontmost.
final class PickerPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var flagsHandler: ((NSEvent.ModifierFlags) -> Void)?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }

    /// ⌘-shortcuts reach the window before the main menu, so ⌘C copies the link instead of hitting Edit → Copy.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown || event.type == .leftMouseUp {
            // How long the key press or click waited before the picker saw it.
            Timing.note("picker \(event.type == .keyDown ? "key" : "click") arrived \(Int((ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000)) ms late")
        }
        if event.type == .keyDown, keyHandler?(event) == true { return }
        if event.type == .flagsChanged { flagsHandler?(event.modifierFlags) }
        super.sendEvent(event)
    }
}

/// Shows one picker at a time; links that arrive while it is open wait their turn.
@MainActor
final class PickerController {
    private let settings: SettingsModel
    private let browsers: BrowserManager
    private let history: HistoryModel
    private let openBrowserSettings: () -> Void
    private var queue = PickerQueue<PickerRequest>()
    private var panel: PickerPanel?
    private var model: PickerModel?
    private var current: PickerRequest?
    private var monitors: [Any] = []
    /// ⌘ was already down when the picker opened (it can be the picker key), so it only counts once released.
    private var rememberKeyBlocked = false
    private var recoveryMode = false
    private var recoveryCancellables = Set<AnyCancellable>()
    /// The recovery panel stepped aside for Settings. Nothing is shown until Settings closes, so no
    /// panel covers the toggles the user went there to change; the link stays queued meanwhile.
    private var recoverySuppressedForSettings = false
    /// The browser the recovery panel offers, fixed when it is shown so the button and the action agree.
    private var recoveryBrowserID: String?

    init(settings: SettingsModel, browsers: BrowserManager, history: HistoryModel, openBrowserSettings: @escaping () -> Void = {}) {
        self.settings = settings
        self.browsers = browsers
        self.history = history
        self.openBrowserSettings = openBrowserSettings
    }

    func enqueue(_ request: PickerRequest) {
        queue.append(request)
        if panel == nil { showNext() }
    }

    private func showNext() {
        guard panel == nil, !recoverySuppressedForSettings, let request = queue.head else { return }
        let s = settings.settings
        let list = browsers.pickerChoices(s, for: request.url)
        guard !PickerQueue<PickerRequest>.needsRecovery(choices: list) else {
            showRecovery(for: request)
            return
        }

        // Preselect the primary profile if it belongs to the browser in use, else that browser's first entry.
        let primary = s.primaryBrowser.flatMap { p in list.firstIndex { $0.target == p } }
        let lastActive = browsers.lastActiveBrowserID.flatMap { id in list.firstIndex { $0.browser.id == id } }
        // What you usually pick for this domain beats everything else.
        let remembered = history.history.preferred(for: request.url).flatMap { d in list.firstIndex { $0.destination == d } }
        let initial: Int
        if let remembered {
            initial = remembered
        } else if let primary, lastActive == nil || list[primary].browser.id == browsers.lastActiveBrowserID {
            initial = primary
        } else {
            initial = lastActive ?? primary ?? 0
        }
        let model = PickerModel(
            url: request.url, sourceName: request.sourceApp?.localizedName, sourceIcon: request.sourceApp?.icon,
            choices: list, showURL: s.showURLInPicker, selection: initial)
        // The full hint line is only shown for the first few opens, then it moves behind a "?" tooltip.
        let hintCount = UserDefaults.standard.integer(forKey: "pickerHintShownCount")
        model.showFullHint = hintCount < 10
        UserDefaults.standard.set(hintCount + 1, forKey: "pickerHintShownCount")
        model.onChoose = { [weak self] index, background in
            self?.choose(index, inBackground: background, remember: self?.model?.remembering ?? false)
        }
        rememberKeyBlocked = NSEvent.modifierFlags.contains(.command)

        let panel = PickerPanel()
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.flagsHandler = { [weak self] flags in self?.flagsChanged(flags) }
        // One screen and one inset for both the width cap and the position, so the panel always fits.
        let bounds = Self.pointerScreenBounds()
        let maxWidth = max(300, bounds.width)
        let host = NSHostingView(rootView: PickerView(model: model, maxWidth: maxWidth))
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size, in: bounds))

        self.panel = panel
        self.model = model
        self.current = request
        recoveryMode = false
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        // Clicking anywhere outside the picker dismisses it.
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.recoveryMode else { return }
                    self.cancelCurrent()
                }
            })
        {
            monitors.append(m)
        }
    }

    private func showRecovery(for request: PickerRequest) {
        let panel = PickerPanel()
        panel.level = .floating
        panel.keyHandler = { [weak self] event in self?.handleRecoveryKey(event) ?? false }
        let browser = preferredRecoveryBrowser()
        recoveryBrowserID = browser?.id
        let installed = !browsers.installed.isEmpty
        let host = NSHostingView(
            rootView: EmptyPickerRecoveryView(
                url: request.url,
                browserName: browser?.name,
                hasInstalledBrowsers: installed,
                openSettings: { [weak self] in
                    self?.hideRecoveryForSettings(); self?.openBrowserSettings()
                },
                copyLink: { [weak self] in self?.copyCurrentLink() },
                openBrowser: { [weak self] in self?.openRecoveryBrowser() },
                cancel: { [weak self] in self?.cancelCurrent() }))
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size, in: Self.pointerScreenBounds()))
        self.panel = panel
        self.current = request
        recoveryMode = true
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        recoveryCancellables.removeAll()
        settings.$settings.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.reevaluateRecovery() }
        }.store(in: &recoveryCancellables)
        browsers.$installed.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.reevaluateRecovery() }
        }.store(in: &recoveryCancellables)
        browsers.$profiles.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.reevaluateRecovery() }
        }.store(in: &recoveryCancellables)
    }

    private func preferredRecoveryBrowser() -> Browser? {
        let installed = browsers.installed
        let primary = settings.settings.primaryBrowser.flatMap { target in installed.first { $0.id == target.browserID } }
        let lastActive = browsers.lastActiveBrowserID.flatMap { id in installed.first { $0.id == id } }
        return primary ?? lastActive ?? installed.first
    }

    private func hideRecoveryForSettings() {
        // The link stays at the head of the queue; settingsDidClose shows the picker or recovery again.
        dismissPanelOnly()
        recoverySuppressedForSettings = true
    }

    /// The Settings window closed: show whatever the queued link needs now, the picker if a browser
    /// was made visible, else the recovery panel again.
    func settingsDidClose() {
        guard recoverySuppressedForSettings else { return }
        recoverySuppressedForSettings = false
        showNext()
    }

    /// Settings, browsers or profiles changed while the recovery panel is up: show the picker if the
    /// link has choices now, else rebuild the panel so it offers what is installed now.
    private func reevaluateRecovery() {
        guard recoveryMode, panel != nil, let current else { return }
        dismissPanelOnly()
        if browsers.pickerChoices(settings.settings, for: current.url).isEmpty {
            showRecovery(for: current)
        } else {
            showNext()
        }
    }

    private func openRecoveryBrowser() {
        guard let current, let id = recoveryBrowserID else { return }
        guard let installed = browsers.browser(withID: id) else {
            // Uninstalled while the panel was up: offer what is there now, and keep the link.
            dismissPanelOnly()
            showRecovery(for: current)
            return
        }
        let primaryProfile = settings.settings.primaryBrowser.flatMap { target in
            target.browserID == installed.id ? target.profileID : nil
        }
        browsers.openOrSwitch(current.url, in: installed, profileID: primaryProfile, inBackground: false, reuseTab: false)
        cancelCurrent()
    }

    private func handleRecoveryKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods.contains(.command) {
            switch chars {
            case "c": copyCurrentLink(); return true
            case "w", ".": cancelCurrent(); return true
            case ",": hideRecoveryForSettings(); openBrowserSettings(); return true
            default: break
            }
        }
        switch event.keyCode {
        case 53: cancelCurrent(); return true
        case 36, 76:
            if recoveryBrowserID != nil { openRecoveryBrowser() } else { copyCurrentLink() }
            return true
        default: return false
        }
    }

    private func copyCurrentLink() {
        guard let current else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(current.url.absoluteString, forType: .string)
        cancelCurrent()
    }

    private func cancelCurrent() {
        guard panel != nil, let current else { return }
        queue.resolve(id: current.id)
        dismiss()
    }

    /// The visible area of the pointer's screen, less a small margin: where the picker must fit.
    private static func pointerScreenBounds() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 816, height: 616)).insetBy(dx: 8, dy: 8)
    }

    /// Centered on the mouse pointer, kept inside `bounds`.
    private func origin(for size: NSSize, in bounds: NSRect) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return origin
    }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        let command = flags.contains(.command)
        if !command { rememberKeyBlocked = false }
        model?.remembering = command && !rememberKeyBlocked
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let count = model.choices.count
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let background = mods.contains(.shift)
        let remember = model.remembering
        // Shift is stripped too, so ⇧1 reads as "1" rather than "!".
        let chars = event.characters(byApplyingModifiers: [])?.lowercased() ?? ""

        switch event.keyCode {
        case 53:  // escape
            cancelCurrent()
            return true
        case 36, 76:  // return, keypad enter
            choose(model.selection, inBackground: background, remember: remember)
            return true
        case 123:  // left
            model.selection = (model.selection - 1 + count) % count
            return true
        case 124, 48:  // right, tab
            model.selection = (model.selection + (mods.contains(.shift) && event.keyCode == 48 ? count - 1 : 1)) % count
            return true
        default:
            break
        }

        if mods.contains(.command) {
            switch chars {
            case "c":
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.url.absoluteString, forType: .string)
                cancelCurrent()
                return true
            case "w", ".":
                cancelCurrent()
                return true
            default:
                break
            }
        }

        if let digit = Int(chars), (1...9).contains(digit), digit <= count {
            choose(digit - 1, inBackground: background, remember: remember)
            return true
        }

        // A letter jumps to the entry (browser or profile name) starting with it; if only one does, it opens.
        if let letter = chars.first, letter.isLetter {
            let matches = model.choices.indices.filter { model.choices[$0].title.lowercased().first == letter }
            if matches.count == 1 {
                choose(matches[0], inBackground: background, remember: remember)
            } else if !matches.isEmpty {
                model.selection = matches.first { $0 > model.selection } ?? matches[0]
            }
            return true
        }
        return false
    }

    private func choose(_ index: Int, inBackground: Bool, remember: Bool = false) {
        guard let model, let current, model.choices.indices.contains(index) else { return }
        let start = ContinuousClock.now
        defer { Timing.report("picker choose", since: start) }
        let choice = model.choices[index]
        if settings.settings.rememberDomains { history.record(current.url, destination: choice.destination, picked: true) }
        // Desktop-app entries have no rule action, so they are only ever opened.
        if remember, choice.deepLink == nil { settings.settings.rules.remember(current.url, to: choice.target) }
        if let deepLink = choice.deepLink {
            browsers.openInApp(deepLink, bundleID: choice.browser.id)
            cancelCurrent()
            return
        }
        // Resolve before opening: the open is queued off the main actor and the picker closes at once.
        cancelCurrent()
        browsers.openOrSwitch(
            current.url, in: choice.browser, profileID: choice.profile?.id, inBackground: inBackground,
            reuseTab: settings.settings.tabReuse != .off)
    }

    private func dismiss() {
        guard panel != nil else { return }
        dismissPanelOnly()
        DispatchQueue.main.async { [weak self] in self?.showNext() }
    }

    private func dismissPanelOnly() {
        guard let panel else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        self.panel = nil
        self.model = nil
        self.current = nil
        recoveryMode = false
        recoverySuppressedForSettings = false
        recoveryBrowserID = nil
        recoveryCancellables.removeAll()
        rememberKeyBlocked = false
        panel.orderOut(nil)
    }

}

// MARK: - View

struct PickerView: View {
    @ObservedObject var model: PickerModel
    let maxWidth: CGFloat

    /// "Chrome, Buffer profile, 2": parts that don't exist are left out.
    private static func accessibilityLabel(for choice: BrowserChoice, shortcut: Int?) -> String {
        var parts: [String]
        if choice.deepLink != nil {
            parts = [choice.title, "desktop app"]
        } else if let profile = choice.profile {
            parts = [choice.browser.name, "\(profile.name) profile"]
        } else {
            parts = [choice.title]
        }
        if let shortcut { parts.append(String(shortcut)) }
        return parts.joined(separator: ", ")
    }

    private static let hint = "⏎ open  ·  ⇧ in background  ·  ⌘ always for this site  ·  ⌘C copy link  ·  esc cancel"
    private static let hintKeys: [(key: String, label: String?)] = [
        ("⏎", "Open"), ("⇧", "Background"), ("⌘", "Always"), ("⌘C", "Copy"), ("esc", nil),
    ]

    /// The host in primary colour and semibold, the rest of the link (scheme, path, query) secondary.
    private static func styledLink(_ url: URL) -> Text {
        // The lock already says https, so the scheme is dropped.
        let full = url.absoluteString.replacingOccurrences(of: "https://", with: "", options: .anchored)
        guard let host = url.host, let range = full.range(of: host) else { return Text(full) }
        return Text(full[..<range.lowerBound]).foregroundColor(.secondary)
            + Text(host).foregroundColor(.primary).fontWeight(.semibold)
            + Text(full[range.upperBound...]).foregroundColor(.secondary)
    }

    private var tilesWidth: CGFloat { CGFloat(model.choices.count) * 88 - 4 }
    /// More tiles than fit on the screen, so the row scrolls.
    private var overflows: Bool { tilesWidth > maxWidth - 24 }

    var body: some View {
        VStack(spacing: 0) {
            if model.showURL {
                linkChip
                    .frame(width: min(max(tilesWidth, 300), maxWidth - 24))
                    .padding(.bottom, 10)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(Array(model.choices.enumerated()), id: \.element.id) { index, choice in
                            Button {
                                if model.click(index) { model.onChoose(index, NSEvent.modifierFlags.contains(.shift)) }
                            } label: {
                                ChoiceTile(
                                    choice: choice, shortcut: index < 9 ? index + 1 : nil, isSelected: index == model.selection,
                                    isPinned: model.remembering && index == model.selection,
                                    remembering: model.remembering
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // Keys are handled by the panel, so buttons must not take focus.
                            .focusable(false)
                            // Continuous, so moving within the tile the picker opened under also selects it.
                            .onContinuousHover { if case .active = $0 { model.pointerEntered(index) } }
                            .accessibilityLabel(Self.accessibilityLabel(for: choice, shortcut: index < 9 ? index + 1 : nil))
                            .accessibilityAddTraits(index == model.selection ? .isSelected : [])
                            .id(index)
                        }
                    }
                }
                // A visible scroller when the row overflows: it shows there is more, and a mouse
                // without horizontal scrolling can still drag it.
                .scrollIndicators(overflows ? .visible : .hidden)
                .frame(width: min(tilesWidth, maxWidth - 24))
                .onAppear {
                    // The preselected tile can be anywhere in a long row; start with it in view.
                    guard overflows else { return }
                    let selection = model.selection
                    DispatchQueue.main.async { proxy.scrollTo(selection, anchor: .center) }
                }
                .onChange(of: model.selection) { _, selection in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(selection, anchor: .center) }
                }
            }
            footer.padding(.top, 9)
        }
        .padding(12)
        .frame(maxWidth: maxWidth)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.12), value: model.selection)
        .animation(.easeOut(duration: 0.15), value: model.remembering)
    }

    /// The link and the app it came from, so you see where it goes before you choose.
    private var linkChip: some View {
        HStack(spacing: 7) {
            Image(systemName: model.url.scheme == "https" ? "lock.fill" : "globe")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Self.styledLink(model.url)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.url.absoluteString)
            Spacer(minLength: 8)
            if let source = model.sourceName {
                HStack(spacing: 5) {
                    if let icon = model.sourceIcon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text("from \(source)")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }

    /// The hint row and the ⌘ banner share one fixed slot, so holding ⌘ never resizes the picker.
    /// The banner is an overlay: its text follows the selected tile, and it must not change the width either.
    private var footer: some View {
        hints
            .opacity(model.remembering ? 0 : 1)
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .overlay { rememberBanner.opacity(model.remembering ? 1 : 0) }
    }

    @ViewBuilder
    private var hints: some View {
        if model.showFullHint {
            HStack(spacing: 12) {
                ForEach(Self.hintKeys, id: \.key) { hint in
                    HStack(spacing: 4) {
                        Keycap(text: hint.key)
                        if let label = hint.label { Text(label) }
                    }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.hint)
        } else {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .help(Self.hint)
        }
    }

    private var rememberBanner: some View {
        HStack(spacing: 5) {
            Image(systemName: "pin.fill")
            let domain = Text(model.domain ?? "this site").fontWeight(.semibold)
            if let target = model.rememberTarget, target.deepLink == nil {
                Text("Always open ") + domain + Text(" in \(target.menuTitle)")
            } else {
                Text("Always open ") + domain + Text(" with the one you pick")
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color.amber)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.amber.opacity(0.14)))
        .accessibilityHidden(!model.remembering)
    }
}

private struct EmptyPickerRecoveryView: View {
    let url: URL
    let browserName: String?
    let hasInstalledBrowsers: Bool
    let openSettings: () -> Void
    let copyLink: () -> Void
    let openBrowser: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No picker destinations are available")
                .font(.headline)
            Text(hasInstalledBrowsers ? "This link is still waiting. Show a browser in Settings, open it directly, copy the link, or cancel." : "No browsers found. Install one, or copy the link.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(url.absoluteString)
            HStack {
                Button("Open Settings") { openSettings() }
                if let browserName {
                    Button("Open in \(browserName)", action: openBrowser).keyboardShortcut(.defaultAction)
                }
                Spacer()
                Button("Copy Link", action: copyLink)
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 410)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }
}

/// A key drawn as a small keycap: "2", "⏎", "⌘C".
private struct Keycap: View {
    let text: String
    var isHighlighted = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHighlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.1)))
                    .shadow(color: .black.opacity(isHighlighted ? 0 : 0.2), radius: 0, y: 0.5)
            )
    }
}

private struct ChoiceTile: View {
    let choice: BrowserChoice
    let shortcut: Int?
    let isSelected: Bool
    /// ⌘ is held and this is the tile a click or Return would remember: the selected one.
    var isPinned = false
    /// ⌘ is held: desktop-app tiles (which can't be remembered) fade.
    var remembering = false

    private var canRemember: Bool { choice.deepLink == nil }

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: choice.browser.icon)
                .resizable()
                .frame(width: 56, height: 56)
                .overlay(alignment: .bottomTrailing) {
                    if let profile = choice.profile {
                        ProfileBadge(profile: profile, avatar: choice.avatar).offset(x: 4, y: 4)
                    }
                }
            Text(choice.title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 76)
                .padding(.top, 4)
            Text(choice.deepLink != nil ? "Desktop app" : choice.profile != nil ? choice.browser.name : " ")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 76)
            if let shortcut {
                Keycap(text: String(shortcut), isHighlighted: isSelected).padding(.top, 4)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .opacity(remembering && !canRemember ? 0.35 : 1)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.24) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.7 : 0), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if isPinned, canRemember {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black.opacity(0.75))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.amber))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .offset(x: 6, y: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

extension Color {
    /// The amber of the app icon's control-tower cab, for the "remember this pick" state.
    static let amber = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 1, green: 0.70, blue: 0.25, alpha: 1)
                : NSColor(srgbRed: 0.78, green: 0.47, blue: 0, alpha: 1)
        })
}

/// The profile's account picture, or its initial on a color derived from the profile directory.
private struct ProfileBadge: View {
    let profile: BrowserProfile
    let avatar: NSImage?

    var body: some View {
        Group {
            if let avatar {
                Image(nsImage: avatar).resizable().scaledToFill()
            } else {
                Text(profile.name.prefix(1).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Self.color(for: profile.id))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
        .shadow(radius: 1)
    }

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red]

    private static func color(for id: String) -> Color {
        // A stable hash: String.hashValue changes between launches.
        palette[id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count]
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
