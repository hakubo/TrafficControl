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
    let choices: [BrowserChoice]
    let showURL: Bool
    @Published var selection: Int
    var onChoose: (Int, Bool) -> Void = { _, _ in }

    init(url: URL, sourceName: String?, choices: [BrowserChoice], showURL: Bool, selection: Int) {
        self.url = url
        self.sourceName = sourceName
        self.choices = choices
        self.showURL = showURL
        self.selection = selection
    }
}

/// A borderless panel that can take keyboard focus without activating TrafficControl,
/// so the app you clicked the link in stays frontmost.
final class PickerPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

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

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
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
        let remembered = history.history.record(for: request.url)?.preferred.flatMap { d in list.firstIndex { $0.destination == d } }
        let initial: Int
        if let remembered {
            initial = remembered
        } else if let primary, lastActive == nil || list[primary].browser.id == browsers.lastActiveBrowserID {
            initial = primary
        } else {
            initial = lastActive ?? primary ?? 0
        }
        let model = PickerModel(
            url: request.url, sourceName: request.sourceApp?.localizedName,
            choices: list, showURL: s.showURLInPicker, selection: initial)
        model.onChoose = { [weak self] index, background in self?.choose(index, inBackground: background) }

        let panel = PickerPanel()
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
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
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) { monitors.append(m) }
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

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let count = model.choices.count
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let background = mods.contains(.shift)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case 53: // escape
            dismiss()
            return true
        case 36, 76: // return, keypad enter
            choose(model.selection, inBackground: background)
            return true
        case 123: // left
            model.selection = (model.selection - 1 + count) % count
            return true
        case 124, 48: // right, tab
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
                return false
            }
        }

        if let digit = Int(chars), (1...9).contains(digit), digit <= count {
            choose(digit - 1, inBackground: background)
            return true
        }

        // A letter jumps to the entry (browser or profile name) starting with it; if only one does, it opens.
        if let letter = chars.first, letter.isLetter {
            let matches = model.choices.indices.filter { model.choices[$0].title.lowercased().first == letter }
            if matches.count == 1 {
                choose(matches[0], inBackground: background)
            } else if !matches.isEmpty {
                model.selection = matches.first { $0 > model.selection } ?? matches[0]
            }
            return true
        }
        return false
    }

    private func choose(_ index: Int, inBackground: Bool) {
        guard let model, let current, model.choices.indices.contains(index) else { return }
        let choice = model.choices[index]
        if settings.settings.rememberDomains { history.record(current.url, destination: choice.destination) }
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
        panel.orderOut(nil)
        DispatchQueue.main.async { [weak self] in self?.showNext() }
    }
}

// MARK: - View

struct PickerView: View {
    @ObservedObject var model: PickerModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(model.choices.enumerated()), id: \.element.id) { index, choice in
                    ChoiceTile(choice: choice, shortcut: index < 9 ? index + 1 : nil, isSelected: index == model.selection)
                        .contentShape(Rectangle())
                        .onHover { if $0 { model.selection = index } }
                        .onTapGesture { model.onChoose(index, NSEvent.modifierFlags.contains(.shift)) }
                }
            }
            if model.showURL {
                VStack(spacing: 2) {
                    Text(model.url.absoluteString)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let source = model.sourceName {
                        Text("from \(source)").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: max(240, CGFloat(model.choices.count) * 84))
            }
            Text("⏎ open  ·  ⇧ in background  ·  ⌘C copy link  ·  esc cancel")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

private struct ChoiceTile: View {
    let choice: BrowserChoice
    let shortcut: Int?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: choice.browser.icon)
                .resizable()
                .frame(width: 56, height: 56)
                .overlay(alignment: .bottomTrailing) {
                    if let profile = choice.profile {
                        ProfileBadge(profile: profile, avatar: choice.avatar).offset(x: 4, y: 4)
                    }
                }
            Text(choice.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(width: 72)
            if choice.profile != nil || choice.deepLink != nil {
                Text(choice.deepLink != nil ? "Desktop app" : choice.browser.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
            Text(shortcut.map(String.init) ?? " ")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : .clear)
        )
    }
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
