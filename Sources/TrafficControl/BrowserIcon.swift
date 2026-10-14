import SwiftUI
import TrafficControlCore

/// A browser's icon; for a profile, with the profile's avatar (or a generic one) in the corner.
struct BrowserIcon: View {
    let browser: Browser
    var hasProfile = false
    var avatar: NSImage?
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: browser.icon)
            .resizable()
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if hasProfile {
                    Group {
                        if let avatar {
                            Image(nsImage: avatar).resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.white, .gray)
                        }
                    }
                    .frame(width: size / 2, height: size / 2)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .offset(x: size / 8, y: size / 8)
                }
            }
    }
}
