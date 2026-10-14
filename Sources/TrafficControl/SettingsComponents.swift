import SwiftUI
import TrafficControlCore

/// A white SF Symbol on a rounded, tinted square, like the icons in System Settings.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(tint.gradient))
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }
}

/// The centered icon, title and blurb at the top of a pane.
struct PaneHeader<Icon: View, Accessory: View>: View {
    let title: String
    let message: String
    @ViewBuilder var icon: Icon
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 6) {
            icon.padding(.bottom, 4)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            accessory.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

extension PaneHeader where Icon == IconTile {
    init(_ pane: SettingsPane, message: String, @ViewBuilder accessory: () -> Accessory) {
        self.init(
            title: pane.title, message: message,
            icon: { IconTile(symbol: pane.symbol, tint: pane.tint, size: 56) }, accessory: accessory)
    }
}

extension PaneHeader where Icon == IconTile, Accessory == EmptyView {
    init(_ pane: SettingsPane, message: String) {
        self.init(pane, message: message) { EmptyView() }
    }
}

var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "–"
    let build = info?["CFBundleVersion"] as? String
    return build.map { "\(version) (\($0))" } ?? version
}
