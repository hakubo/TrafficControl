import AppKit
import SwiftUI
import TrafficControlCore

struct PickerRequest {
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
    @Published var selection: Int
    /// The tile under the pointer: a lighter highlight that never changes what Return opens.
    @Published var hovered: Int?
    /// ⌘ is held: the pick also becomes the rule for this domain.
    @Published var remembering = false
    /// Full keyboard hint line vs. a "?" tooltip once the user has seen it a few times.
    var showFullHint = true
    var onChoose: (Int, Bool) -> Void = { _, _ in }

    /// "github.com", the part of the link a remembered pick applies to.
    var domain: String? { LinkAddress.of(url, depth: 0) }

    /// The entry a ⌘-click or ⌘-Return would remember: the hovered tile, else the selected one.
    var rememberTarget: BrowserChoice? {
        let index = hovered ?? selection
        return choices.indices.contains(index) ? choices[index] : nil
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
    private var queue: [PickerRequest] = []
    private var panel: PickerPanel?
    private var model: PickerModel?
    private var current: PickerRequest?
    private var monitors: [Any] = []
    /// ⌘ was already down when the picker opened (it can be the picker key), so it only counts once released.
    private var rememberKeyBlocked = false

    init(settings: SettingsModel, browsers: BrowserManager, history: HistoryModel) {
        self.settings = settings
        self.browsers = browsers
        self.history = history
    }

    func enqueue(_ request: PickerRequest) {
        queue.append(request)
        if panel == nil { showNext() }
    }

    private func showNext() {
        guard panel == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        let s = settings.settings
        let list = browsers.pickerChoices(s, for: request.url)
        guard !list.isEmpty else {
            NSSound.beep()
            showNext()
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
        let host = NSHostingView(rootView: PickerView(model: model))
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))

        self.panel = panel
        self.model = model
        self.current = request
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        // Clicking anywhere outside the picker dismisses it.
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        {
            monitors.append(m)
        }
    }

    /// Centered on the mouse pointer, kept inside the visible area of its screen.
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let bounds = (screen?.visibleFrame ?? .zero).insetBy(dx: 8, dy: 8)
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
            dismiss()
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
                dismiss()
                return true
            case "w", ".":
                dismiss()
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
        let choice = model.choices[index]
        if settings.settings.rememberDomains { history.record(current.url, destination: choice.destination, picked: true) }
        // Desktop-app entries have no rule action, so they are only ever opened.
        if remember, choice.deepLink == nil { settings.settings.rules.remember(current.url, to: choice.target) }
        if let deepLink = choice.deepLink {
            browsers.openInApp(deepLink, bundleID: choice.browser.id)
            dismiss()
            return
        }
        browsers.openOrSwitch(
            current.url, in: choice.browser, profileID: choice.profile?.id, inBackground: inBackground,
            reuseTab: settings.settings.tabReuse != .off)
        dismiss()
    }

    private func dismiss() {
        guard let panel else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        self.panel = nil
        self.model = nil
        self.current = nil
        rememberKeyBlocked = false
        panel.orderOut(nil)
        DispatchQueue.main.async { [weak self] in self?.showNext() }
    }
}

// MARK: - View

struct PickerView: View {
    @ObservedObject var model: PickerModel

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

    var body: some View {
        VStack(spacing: 0) {
            if model.showURL {
                linkChip
                    .frame(width: max(tilesWidth, 300))
                    .padding(.bottom, 10)
            }
            HStack(spacing: 4) {
                ForEach(Array(model.choices.enumerated()), id: \.element.id) { index, choice in
                    Button {
                        model.onChoose(index, NSEvent.modifierFlags.contains(.shift))
                    } label: {
                        ChoiceTile(
                            choice: choice, shortcut: index < 9 ? index + 1 : nil, isSelected: index == model.selection,
                            isHovered: index == model.hovered,
                            isPinned: model.remembering && index == (model.hovered ?? model.selection),
                            remembering: model.remembering
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Keys are handled by the panel, so buttons must not take focus.
                    .focusable(false)
                    .onHover { if $0 { model.hovered = index } else if model.hovered == index { model.hovered = nil } }
                    .accessibilityLabel(Self.accessibilityLabel(for: choice, shortcut: index < 9 ? index + 1 : nil))
                    .accessibilityAddTraits(index == model.selection ? .isSelected : [])
                }
            }
            footer.padding(.top, 9)
        }
        .padding(12)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.12), value: model.selection)
        .animation(.easeOut(duration: 0.12), value: model.hovered)
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
    /// The banner is an overlay: its text follows the hovered tile, and it must not change the width either.
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
    let isHovered: Bool
    /// ⌘ is held and this is the tile a click or Return would remember: the hovered one, else the selected one.
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
                .fill(isSelected ? Color.accentColor.opacity(0.24) : isHovered ? Color.primary.opacity(0.06) : .clear)
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
