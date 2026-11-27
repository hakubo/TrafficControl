import Foundation
import TrafficControlCore

/// Finds a Slack workspace's team ID from its subdomain with Slack's sign-in endpoint, which needs no
/// login. Only the subdomain is sent, to slack.com, the same company the link points to.
enum SlackWorkspaceLookup {
    /// Long enough for a normal connection, short enough that a click never feels stuck; on timeout the link opens in the browser.
    static let timeout: TimeInterval = 2

    static func teamID(for workspace: String) async -> String? {
        var request = URLRequest(url: URL(string: "https://slack.com/api/auth.findTeam")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "domain", value: workspace)]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return SlackLink.teamID(fromFindTeamResponse: data)
    }
}
