import SwiftUI
import TrafficControlCore

/// What the menu bar popover shows and does; AppDelegate fills it in each time the popover opens.
@MainActor
final class MenuBarModel: ObservableObject {
    @Published var override: TemporaryOverride?
    /// Whether the pasteboard probably holds a web URL (detected without reading it).
    @Published var clipboardHasURL = false

    var startOverride: (BrowserTarget) -> Void = { _ in }
    var stopOverride: () -> Void = {}
    var openClipboard: () -> Void = {}
    var makeDefault: () -> Void = {}
    var showSettings: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var buyMeACoffee: () -> Void = {}
}

struct MenuBarPopover: View {
    @ObservedObject var model: MenuBarModel
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @EnvironmentObject private var history: HistoryModel
    @EnvironmentObject private var updater: UpdaterModel
    @EnvironmentObject private var defaultStatus: DefaultBrowserStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !choices.isEmpty {
                sectionLabel("Send All Links To", detail: "for 1 hour")
                tray
                if let override = model.override {
                    activeOverride(override)
                }
            }
            if defaultStatus.isDefault {
                Button(action: model.openClipboard) {
                    Label("Open Link from Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(RowButtonStyle())
                .labelStyle(.titleAndIcon)
                .disabled(!model.clipboardHasURL)
                .padding(.top, 12)
            }
            if !recent.isEmpty {
                sectionLabel("Recent", detail: nil)
                recentList
            }
            Divider().padding(.top, 12).padding(.bottom, 6)
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("TrafficControl").font(.system(size: 14, weight: .semibold))
                statusPill
            }
            Spacer(minLength: 0)
            if !defaultStatus.isDefault {
                Button("Make Default", action: model.makeDefault)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
        }
    }

    private var statusPill: some View {
        let ok = defaultStatus.isDefault
        let color: Color = ok ? .green : .orange
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: ok ? color : .clear, radius: 3)
            Text(ok ? "Routing your links" : "Not the default browser")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 2)
        .background(color.opacity(0.16), in: Capsule())
    }

    private func sectionLabel(_ title: String, detail: String?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            if let detail {
                Text(detail).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 14).padding(.bottom, 7)
    }

    // MARK: Send All Links To

    private var choices: [BrowserChoice] {
        browsers.orderedChoices(settings.settings, includeHidden: false)
    }

    private var tray: some View {
        HStack(spacing: 4) {
            ForEach(choices) { choice in
                let isOn = model.override?.target == choice.target
                Button {
                    isOn ? model.stopOverride() : model.startOverride(choice.target)
                } label: {
                    BrowserIcon(
                        browser: choice.browser, hasProfile: choice.profile != nil, avatar: choice.avatar,
                        size: 24)
                }
                .buttonStyle(TraySlotStyle(isOn: isOn))
                .help(isOn ? "Stop sending all links to \(choice.menuTitle)" : choice.menuTitle)
            }
        }
        .padding(4)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func activeOverride(_ override: TemporaryOverride) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let left = max(0, override.until.timeIntervalSince(context.date))
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.primary.opacity(0.12), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: left / 3600)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(browsers.title(for: override.target)).lineLimit(1)
                    Text(
                        "Every link until \(override.until.formatted(date: .omitted, time: .shortened)) · \(Int((left / 60).rounded(.up))) min left"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                Spacer(minLength: 0)
                Button("Stop", action: model.stopOverride).controlSize(.small)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 8)
        }
    }

    // MARK: Recent

    private var recent: [DomainRecord] {
        Array(history.history.recent.prefix(3))
    }

    private var recentList: some View {
        VStack(spacing: 0) {
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                if index > 0 { Divider().padding(.leading, 10) }
                HStack(spacing: 8) {
                    Text(record.domain).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(record.lastOpened, format: .relative(presentation: .named))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if let destination = record.lastDestination {
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        destinationIcon(destination)
                            .help(browsers.title(for: destination))
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 7)
            }
        }
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder private func destinationIcon(_ destination: LinkDestination) -> some View {
        switch destination {
        case .browser(let target):
            if let choice = choices.first(where: { $0.target == target }) {
                BrowserIcon(browser: choice.browser, hasProfile: choice.profile != nil, avatar: choice.avatar, size: 16)
            } else if let browser = browsers.browser(withID: target.browserID) {
                BrowserIcon(browser: browser, hasProfile: target.profileID != nil, size: 16)
            }
        case .app(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button(action: model.showSettings) { Label("Settings", systemImage: "gearshape") }
                .keyboardShortcut(",")
            if updater.isAvailable {
                Button(action: model.checkForUpdates) { Label("Check for Updates", systemImage: "arrow.down.circle") }
                    .labelStyle(.iconOnly)
                    .help("Check for Updates…")
            }
            Button(action: model.buyMeACoffee) { Label("Buy Me a Coffee", systemImage: "cup.and.saucer") }
                .labelStyle(.iconOnly)
                .help("Buy Me a Coffee…")
            Spacer(minLength: 0)
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(RowButtonStyle(compact: true))
        .labelStyle(.titleAndIcon)
        .font(.system(size: 12))
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A borderless row that highlights on hover, like a menu item.
private struct RowButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? (compact ? .secondary : .primary) : .tertiary)
            .padding(.horizontal, compact ? 6 : 10).padding(.vertical, compact ? 4 : 7)
            .background(
                RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                    .fill(.primary.opacity(configuration.isPressed ? 0.12 : isHovered && isEnabled ? 0.07 : 0))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct TraySlotStyle: ButtonStyle {
    let isOn: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isOn
                            ? Color.accentColor.opacity(0.22)
                            : .primary.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.07 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isOn ? 0.6 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isOn)
    }
}
