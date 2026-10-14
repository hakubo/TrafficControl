import SwiftUI
import TrafficControlCore

/// The sections of the Settings window, shown in its sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, browsers, rules, apps, updates

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .browsers: "Browsers"
        case .rules: "Rules"
        case .apps: "Apps"
        case .updates: "Software Update"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .browsers: "globe"
        case .rules: "arrow.triangle.branch"
        case .apps: "square.grid.2x2.fill"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .browsers: .blue
        case .rules: .purple
        case .apps: .orange
        case .updates: .green
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var updater: UpdaterModel
    @EnvironmentObject private var defaultStatus: DefaultBrowserStatus
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section {
                    ForEach([SettingsPane.general, .browsers, .rules, .apps]) { sidebarRow($0) }
                }
                if updater.isAvailable {
                    Section { sidebarRow(.updates) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralSettingsView()
                case .browsers: BrowsersSettingsView()
                case .rules: RulesSettingsView()
                case .apps: AppsSettingsView()
                case .updates: UpdatesSettingsView()
                }
            }
            .navigationTitle((pane ?? .general).title)
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        NavigationLink(value: pane) {
            HStack {
                Label {
                    Text(pane.title)
                } icon: {
                    IconTile(symbol: pane.symbol, tint: pane.tint)
                }
                Spacer()
                if pane == .general && !defaultStatus.isDefault {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.white, .orange)
                        .help("TrafficControl isn't your default browser")
                }
            }
        }
    }
}
