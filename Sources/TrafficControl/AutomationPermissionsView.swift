import SwiftUI
import TrafficControlCore

/// Each supported browser's Automation permission, with a button that asks macOS for the missing ones now
/// instead of on the first link click.
struct AutomationPermissionsView: View {
    @EnvironmentObject private var browsers: BrowserManager
    @State private var statuses: [String: OpenTabFinder.Permission] = [:]
    @State private var isAsking = false

    private var supported: [Browser] { browsers.installed.filter { OpenTabFinder.supports($0.id) } }
    private var askable: [String] { supported.map(\.id).filter { statuses[$0] == .notAsked } }

    var body: some View {
        if !supported.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(supported) { browser in
                    HStack(spacing: 8) {
                        BrowserIcon(browser: browser, size: 18)
                        Text(browser.name)
                        Spacer()
                        statusLabel(statuses[browser.id])
                    }
                }
                HStack {
                    Button(isAsking ? "Waiting for macOS…" : "Set up now") { ask() }
                        .disabled(isAsking || askable.isEmpty)
                    Button("Open Automation Settings") { NSWorkspace.shared.open(Links.automationSettings) }
                        .buttonStyle(.link)
                    Spacer()
                }
                Text("macOS can only ask about a browser that is running, so open the ones you use first. To change an answer later, use System Settings → Privacy & Security → Automation.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .onAppear(perform: refresh)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refresh() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refresh() }
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: OpenTabFinder.Permission?) -> some View {
        switch status {
        case .allowed: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied: Label("Denied", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .notAsked: Label("Not asked", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        case .notRunning: Label("Open the browser to check", systemImage: "moon.zzz").foregroundStyle(.secondary)
        case .unknown, nil: Label("Unknown", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    /// Reads every status without prompting. The call can wait on the browser, so it runs off the main thread.
    private func refresh() {
        let ids = supported.map(\.id)
        Task.detached(priority: .userInitiated) {
            let found = Dictionary(uniqueKeysWithValues: ids.map { ($0, OpenTabFinder.permission(for: $0, prompt: false)) })
            await MainActor.run { apply(found) }
        }
    }

    /// Prompts for each running browser that hasn't been asked, one after another.
    private func ask() {
        let ids = askable
        isAsking = true
        Task.detached(priority: .userInitiated) {
            let found = Dictionary(uniqueKeysWithValues: ids.map { ($0, OpenTabFinder.permission(for: $0, prompt: true)) })
            await MainActor.run {
                apply(found)
                isAsking = false
                refresh()
            }
        }
    }

    private func apply(_ found: [String: OpenTabFinder.Permission]) {
        for (id, status) in found {
            statuses[id] = status
            OpenTabFinder.note(status, for: id)
        }
    }
}
